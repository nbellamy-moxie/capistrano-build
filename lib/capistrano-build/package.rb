Capistrano::Configuration.instance(:must_exist).load do
  
  namespace :setup do
      desc "set variables"
      task :set_vars, :roles => :build do 
        set :arch, capture('dpkg --print-architecture').chomp
        set :binary_base, "#{application}/main/binary-#{arch}"
        set :binary_dir, "#{dist_dir}/#{binary_base}"
        set :package_base, "pool/#{application}/#{branch}"
        set :package_dir, "#{dist_dir}/#{package_base}"
        set :index_base, "#{application}/indexes"
        set :index_dir, "#{dist_dir}/#{index_base}"
        set :app_dist_dir, "#{dist_dir}/#{application}"
        set :description, "#{application} release - #{branch} #{release_name}"
        set :release_path, "#{deploy_to}/releases/#{branch}-#{release_name}"
        set :build_vars, "true"
        set :bundle_dir, "vendor/bundle"
      end
    end

  namespace :build do

      def check_or_make_dir(dir)
        run "if [ ! -d #{dir} ]; then sudo mkdir -p #{dir} && sudo chown #{user}:#{user} #{dir};fi"
      end

      
      desc "get a tag or branch"
      task :get_code, :roles => :build do
        git_branch,git_remote=capture("git ls-remote #{repository} #{branch}").split()
        run "if [ ! -d #{release_path} ];then git clone -q #{repository} #{release_path};if [ '#{branch}' != 'master' ]; then cd #{release_path};git checkout #{git_branch} -q -b #{branch};fi ;fi"
        run "cd #{release_path}; git pull origin #{git_remote} -q; git reset --hard #{git_branch};git submodule -q init  && git submodule -q update "
      end


      desc "package the build"
      task :package_build, :roles => :build do
        
        fpm=capture "which fpm" rescue nil
        run "gem install fpm --no-rdoc --no-ri" if fpm.nil?
        
        check_or_make_dir(package_dir)
        
        set :package_name, "#{application}-#{branch}-#{release_name}.deb"
        
        ignore=fpm_ignore.map{|a| "-x '**/#{a}'"}.join(', ')
        
        run "if [ ! -f #{package_dir}/#{package_name} ];then fpm -t deb -s dir -a #{arch} -n #{application} -v #{branch} --iteration #{release_name} -p #{package_dir}/#{package_name} #{ignore} -m #{creator} --description '#{description}' #{release_path}; fi"
      end

      task :update_repo, :roles => :build do
        s3cmd=capture('which s3cmd')
        sudo "apt-get -y install s3cmd" if s3cmd.empty?
        check_or_make_dir(app_dist_dir)
        check_or_make_dir(index_dir)
        run "cd #{app_dist_dir};s3cmd sync s3://#{bucket}/dists/#{application}/ ."
        run "cd #{package_dir};s3cmd sync s3://#{bucket}/dists/#{package_base}/ ."
        count = fetch(:keep_releases, 5).to_i
        releases = capture("ls -xt #{package_dir}").split.reverse
        d = (releases - releases.last(count)).map{ |r| File.join(package_dir, r )}.join(" ")
        try_sudo "rm #{d}" unless d.empty?
        run "cd /mnt/builds/;dpkg-scanpackages -m dists/#{package_base} /dev/null > #{index_dir}/#{branch}"
        run "s3cmd sync #{package_dir}/* s3://#{bucket}/dists/#{package_base}/ --delete-removed"
        packages_file
      end



      task :packages_file, :roles => :build do  
        check_or_make_dir(binary_dir)
        run "cat #{index_dir}/* |gzip -c9 > #{binary_dir}/Packages.gz"
        run "s3cmd sync #{app_dist_dir}/* s3://#{bucket}/dists/#{application}/"
      end

      desc "clean up a packaged build"
      task :clean_package_build, :roles => :build do
        
        run "rm -rf #{package_dir}"
        run "rm -rf #{index_dir}/#{branch}"
        run "s3cmd del s3://#{bucket}/dists/#{package_base}/ --recursive"
        run "s3cmd del s3://#{bucket}/dists/#{index_base}/#{branch}"
        packages_file
      end


      desc "build release"
      task :default, :roles => :build do
        get_code
        deploy.create_symlink
        bundle.install  
        build_tasks.each do |t| 
          if task_exists?(t)
            begin
              eval(t)
            rescue => e
              puts "Error => #{e}"
            end 
          else 
            puts "Task #{t} not found"
          end
        end
        package_build
        update_repo
      end
      
    end

    #non-build namespace
    def task_exists?(task)
      top.find_task(task.gsub('.',":")) ? true : false
    end

    build_tasks=build.tasks.keys.map {|n| n="build:"+n.to_s}
    build_tasks << "build"
    # initialize things on build tasks.
    on :start, :only => build_tasks do
      
      if roles[:build].servers.empty?
        instance = ENV["instance"]
        if instance.nil?
          puts "Please run with instance=<server>, or define in cap config file"
          exit          
        else
          role :build, ENV["instance"]
        end
      end
      ENV['ROLES']='build'
      setup.set_vars unless exists?(:build_vars)
    end

    on :before, :only => build_tasks do
        setup.set_vars unless exists?(:build_vars)
    end
    

  end