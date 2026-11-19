Rails.application.routes.draw do
  resources :accounts, only: %i[index]
  resources :glidepaths, only: %i[show]
  resource :dashboard, only: [:show]
  resources :benefits, only: %i[index]
  resources :employments, only: %i[index]
  resources :pensions, only: %i[index]
  resource :projection, only: [:show] do
    get :details
  end
  resource :simulator, only: [:show]
  resource :what_if, only: [:show]
  resource :sample_notice, only: [:destroy]
  resources :users, only: %i[new create edit update] do
    resources :accounts, only: %i[new create edit update destroy]
    resources :benefits, only: %i[new create edit update destroy]
    resources :employments, only: %i[edit update]
    resources :pensions, only: %i[new create edit update destroy]
  end

  scope '/settings' do
    resource :household, only: %i[show update]
    resource :portfolio, only: %i[show update]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'dashboards#show'
end
