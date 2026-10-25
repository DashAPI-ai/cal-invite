# frozen_string_literal: true

require "cgi"
require "fileutils"
require "rdoc"

# Post-processes the RDoc site written by `rake rdoc` so search engines, link
# previews and AI agents can use it. For every HTML page it writes a Markdown
# copy, a <head> block with canonical, Open Graph and Twitter tags, and a
# download link. It also writes robots.txt, sitemap.xml and llms.txt.
module DocsSite
  BASE_URL = "https://dashapi-ai.github.io/cal-invite/"
  SITE_NAME = "CalInvite"
  REPO_URL = "https://github.com/DashAPI-ai/cal-invite"
  SITE_DESCRIPTION = "Ruby gem that generates calendar invitations (URLs and .ics files) " \
                     "for Google Calendar, Outlook, Office 365, Yahoo, Apple iCal and generic .ics clients."
  IMAGE_PATH = "assets/social/cal-invite-github.png"
  IMAGE_ALT = "CalInvite: calendar invitations for Ruby"
  IMAGE_WIDTH = 1280
  IMAGE_HEIGHT = 640
  DESCRIPTION_LIMIT = 160

  # Matches the tags RDoc's template emits for description and social cards,
  # so they can be replaced rather than duplicated.
  RDOC_META = /<meta\s[^>]*?\b(?:name|property)="(?:description|og:[^"]*|twitter:[^"]*)"[^>]*>\s*/m
  MARKER = /<!-- docs-site:(\w+) -->.*?<!-- \/docs-site:\1 -->\n?/m
  TOP_NAV = /<main[^>]*>/
  THEME_TOGGLE = "<!-- Theme toggle button -->"

  Page = Struct.new(:html, :md, :title, :heading, :description, :markdown, :api)

  module_function

  # Writes the extras into +doc_dir+. Run from the project root.
  def build(doc_dir = "doc", root: File.expand_path("..", __dir__))
    classes = api_markdown(root)
    pages = Dir.glob("**/*.html", base: doc_dir).sort.map do |html|
      page_for(doc_dir, html, classes, root)
    end
    pages.sort_by! { |page| [page.html == "index.html" ? 0 : 1, page.html] }

    pages.each do |page|
      write(doc_dir, page.md, page.markdown)
      write(doc_dir, page.html, inject_head(read(doc_dir, page.html), page))
    end

    write(doc_dir, "robots.txt", robots_txt)
    write(doc_dir, "sitemap.xml", sitemap_xml(pages))
    write(doc_dir, "llms.txt", llms_txt(pages))
    FileUtils.mkdir_p(File.join(doc_dir, File.dirname(IMAGE_PATH)))
    FileUtils.cp(File.join(root, IMAGE_PATH), File.join(doc_dir, IMAGE_PATH))
    pages
  end

  def page_for(doc_dir, html, classes, root)
    title = CGI.unescapeHTML(read(doc_dir, html)[%r{<title>(.*?)</title>}m, 1].to_s).strip
    api = classes.key?(html)
    markdown, summary = api ? classes.fetch(html) : [source_markdown(html, root), nil]
    heading = markdown[/\A# (.+)$/, 1]&.strip || File.basename(html, ".html").sub(/_(md|txt)\z/, "")
    description = if html == "index.html"
                    SITE_DESCRIPTION
                  elsif api
                    summary || "API reference for #{heading}"
                  else
                    first_paragraph(markdown) || title
                  end
    md = html.delete_suffix(".html").sub(/_(md|txt)\z/, "") + ".md"
    Page.new(html, md, title, heading, truncate(description), markdown, api)
  end

  # Markdown source for a page that RDoc renders from a Markdown file.
  def source_markdown(html, root)
    source = if html == "index.html"
               "README.md"
             else
               html.delete_suffix(".html").sub(/_(md|txt)\z/) { ".#{Regexp.last_match(1)}" }
             end
    path = File.join(root, source)
    raise "no Markdown source for #{html} (expected #{source})" unless File.file?(path)

    File.read(path)
  end

  # Returns { html_path => [markdown, summary] } for each class and module.
  # RDoc has no public "parse only" API, so this runs its parser directly and
  # reads the resulting store. Output is the comment text as written in the
  # source, which keeps Markdown and YARD tags intact.
  def api_markdown(root)
    Dir.chdir(root) do
      options = RDoc::Options.new
      options.parse(%w[--quiet --markup markdown lib])
      options.finish
      rdoc = RDoc::RDoc.new
      rdoc.options = options
      rdoc.store = RDoc::Store.new(options)
      rdoc.send(:parse_files, options.files)
      rdoc.store.complete(options.visibility)

      rdoc.store.all_classes_and_modules.to_h do |klass|
        summary = first_paragraph(text_of(klass.comment))
        [File.join(*klass.full_name.split("::")) + ".html", [class_markdown(klass), summary]]
      end
    end
  end

  def class_markdown(klass)
    kind = klass.is_a?(RDoc::NormalClass) ? "class" : "module"
    lines = ["# #{klass.full_name}", "", text_of(klass.comment), ""]
    lines << "_#{kind}_ defined in `#{klass.in_files.first&.relative_name}`"
    lines << "" << "Superclass: `#{superclass_name(klass)}`" if kind == "class"
    lines << "" << "Includes: #{klass.includes.map { |i| "`#{i.name}`" }.join(", ")}" if klass.includes.any?

    constants = klass.constants.select { |c| c.visibility == :public }
    unless constants.empty?
      lines << "" << "## Constants" << ""
      constants.each do |c|
        lines << "### `#{c.name}`" << "" << "Value: `#{c.value}`" << "" << text_of(c.comment) << ""
      end
    end

    attributes = klass.attributes.select { |a| a.visibility == :public }
    unless attributes.empty?
      lines << "" << "## Attributes" << ""
      attributes.each do |a|
        lines << "### `#{a.name}` (#{a.rw})" << "" << text_of(a.comment) << ""
      end
    end

    public_methods = klass.method_list.select { |m| m.visibility == :public }
    groups = {
      "Class methods" => public_methods.select(&:singleton),
      "Instance methods" => public_methods.reject(&:singleton)
    }
    groups.each do |heading, list|
      next if list.empty?

      lines << "" << "## #{heading}" << ""
      list.sort_by(&:name).each do |m|
        lines << "### `#{m.name}#{m.params}`" << "" << text_of(m.comment) << ""
      end
    end

    lines.join("\n").gsub(/\n{3,}/, "\n\n").strip + "\n"
  end

  def superclass_name(klass)
    sup = klass.superclass
    sup.respond_to?(:full_name) ? sup.full_name : sup.to_s
  end

  def text_of(comment)
    comment.respond_to?(:text) ? comment.text.to_s.strip : ""
  end

  def first_paragraph(markdown)
    markdown.split(/\n\s*\n/).each do |block|
      text = block.strip
      next if text.empty? || text.match?(/\A(?:#|```|[-*>|<_]|\d+\.)/)

      return text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').delete("`*").gsub(/\s+/, " ")
    end
    nil
  end

  def truncate(text)
    return text if text.length <= DESCRIPTION_LIMIT

    head = text[0, DESCRIPTION_LIMIT - 3].sub(/\s+\S*\z/, "")
    "#{head}..."
  end

  def inject_head(html, page)
    html = html.gsub(MARKER, "").gsub(RDOC_META, "")
    url = page_url(page.html)
    image = BASE_URL + IMAGE_PATH
    title = CGI.escapeHTML(page.title)
    description = CGI.escapeHTML(page.description)

    head = <<~HTML
      <!-- docs-site:head -->
      <meta name="description" content="#{description}">
      <link rel="canonical" href="#{url}">
      <link rel="alternate" type="text/markdown" href="#{File.basename(page.md)}" title="Markdown">
      <meta property="og:type" content="website">
      <meta property="og:site_name" content="#{SITE_NAME}">
      <meta property="og:title" content="#{title}">
      <meta property="og:description" content="#{description}">
      <meta property="og:url" content="#{url}">
      <meta property="og:image" content="#{image}">
      <meta property="og:image:width" content="#{IMAGE_WIDTH}">
      <meta property="og:image:height" content="#{IMAGE_HEIGHT}">
      <meta property="og:image:alt" content="#{IMAGE_ALT}">
      <meta property="og:locale" content="en_US">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{title}">
      <meta name="twitter:description" content="#{description}">
      <meta name="twitter:image" content="#{image}">
      </head>
      <!-- /docs-site:head -->
    HTML

    export = <<~HTML
      <!-- docs-site:export -->
      <p class="md-export">
        <a href="#{File.basename(page.md)}" download>Download as Markdown</a>
        <span aria-hidden="true">&middot;</span>
        <a href="#{"../" * page.html.count("/")}llms.txt">llms.txt</a>
      </p>
      <!-- /docs-site:export -->
    HTML

    repo = <<~HTML
      <!-- docs-site:repo -->
      <a href="#{REPO_URL}" class="navbar-repo" target="_blank" rel="noopener">GitHub</a>
      <!-- /docs-site:repo -->
    HTML

    # RDoc's template never closes <head>, so the block closes it here.
    html = html.sub(/<body\b/) { "#{head}#{Regexp.last_match(0)}" }
    raise "no <body> in #{page.html}" unless html.include?("<body")
    raise "no theme toggle in #{page.html}" unless html.include?(THEME_TOGGLE)

    html = html.sub(THEME_TOGGLE) { "#{repo}#{THEME_TOGGLE}" }
    html.sub(TOP_NAV) { |tag| "#{tag}\n#{export}" }.tap do |out|
      raise "no <main> in #{page.html}" if out == html
    end
  end

  def page_url(html)
    html == "index.html" ? BASE_URL : BASE_URL + html
  end

  def robots_txt
    <<~TXT
      User-agent: *
      Allow: /

      Sitemap: #{BASE_URL}sitemap.xml
    TXT
  end

  def sitemap_xml(pages)
    urls = pages.map { |page| "  <url>\n    <loc>#{CGI.escapeHTML(page_url(page.html))}</loc>\n  </url>" }
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{urls.join("\n")}
      </urlset>
    XML
  end

  # Follows the llms.txt convention: H1 name, blockquote summary, then link
  # lists. Each link points at the Markdown copy of the page.
  def llms_txt(pages)
    entry = lambda do |page|
      "- [#{page.heading}](#{BASE_URL}#{page.md}): #{page.description}"
    end
    guides = pages.reject(&:api)
    api = pages.select(&:api).sort_by(&:heading)

    <<~TXT
      # #{SITE_NAME}

      > #{SITE_DESCRIPTION}

      Every page is available as Markdown at the URL shown in its link. The API reference is generated from the source code.

      ## Guides

      #{guides.map(&entry).join("\n")}

      ## API reference

      #{api.map(&entry).join("\n")}
    TXT
  end

  def read(doc_dir, rel)
    File.read(File.join(doc_dir, rel))
  end

  def write(doc_dir, rel, content)
    path = File.join(doc_dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
