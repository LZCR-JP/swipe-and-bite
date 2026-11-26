Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  devise_for :users
  root to: "pages#home"
  get "about", to: "pages#about", as: :about

  get "restaurant_photo", to: "restaurant_photos#show", as: :restaurant_photo

  # Host side (logged in)
  resources :nomikais do

    member do
      get :progress
      patch :close

      get :recommendations,
          action: :recommendations_landing,
          as: :recommendations_landing

      post :recommendations

      patch "candidates/:candidate_id/select",
            action: :select_candidate,
            as: :select_candidate
    end
  end

  # Colleague side (no account, identified by tokens or a join code)
  get "join", to: "join_codes#new", as: :join_code
  post "join", to: "join_codes#create", as: nil

  get "join/code/:code", to: "participants#new", as: :join_with_code
  post "join/code/:code", to: "participants#create"

  get "invite/:invite_token", to: "participants#new", as: :invite
  post "invite/:invite_token", to: "participants#create"

  get "join/:share_token", to: "participants#new", as: :join
  post "join/:share_token", to: "participants#create"

  resources :participants, only: :show, param: :token do
    resources :swipes, only: %i[index create] do
      post :finish, on: :collection
    end
    resources :candidate_votes, only: :create
  end
end
