namespace :spree_yandex_market do
  desc "Copies all migrations and runs them"
  task :install do
    Rake::Task['spree_yandex_market:install:add_migrations'].invoke
    Rake::Task['spree_yandex_market:install:run_migrations'].invoke
  end

  namespace :install do

    desc "Copies all migrations"
    task :add_migrations do
      run 'bundle exec rake railties:install:migrations FROM=spree_blogging_spree'
    end

    desc "Runs all migrations"
    task :run_migrations do
      run_migrations = options[:auto_run_migrations] || ['', 'y', 'Y'].include?(ask 'Would you like to run the migrations now? [Y/n]')
      if run_migrations
        run 'bundle exec rake db:migrate'
      else
        puts 'Skipping rake db:migrate, don\'t forget to run it!'
      end
    end

  end

end
