Spree::Core::Engine.routes.draw do

  namespace :admin do
    resource :yandex_market_settings do
      member do
        match :general,       via: [:get, :post,], :to => 'yandex_market_settings#general', :as => :general
        match :currency,      via: [:get, :post,], :to => 'yandex_market_settings#currency', :as => :currency
        match :export_files,  via: [:get, :post,], :to => 'yandex_market_settings#export_files', :as => :export_files
        match :ware_property, via: [:get, :post,], :to => 'yandex_market_settings#ware_property', :as => :ware_property
        match :run_export,    via: [:get,],        :to => 'yandex_market_settings#run_export', :as => :run_export
      end
    end
  end

end
