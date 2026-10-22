Rails.application.routes.draw do
  get "calendars/index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "calendars#index"

  # resources :calendars, only: [:index] do
  #   get 'download_ics', on: :collection
  # end

  resources :calendars do
    collection do
      get :download_ics
      post :send_test_email  # This creates the send_test_email_calendars_path helper
    end
  end

  # Demonstrates persisting uid/sequence and the send -> reschedule -> cancel
  # lifecycle for a real RSVP-capable invite. See CONFIGURATION.md.
  # GET /meetings/:id.ics serves a cached .ics file; see MeetingsController#show.
  resources :meetings, only: [:index, :show, :new, :create] do
    member do
      patch :reschedule
      post :cancel
    end
  end

  # Illustrative inbound-reply webhook target. Not wired to a real inbound
  # email provider — see EventRepliesController's comments.
  post "event_replies", to: "event_replies#create"
end
