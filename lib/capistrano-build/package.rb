namespace :build do

    set :aws_key, "AKIAIXSKQJYYUA5T3BFA"
    set :aws_secret, "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"
    set :arch, capture('dpkg --print-architecture').chomp
    set :dist_dir, "/mnt/builds/dists"
    set :fpm_ignore, ["config/mongo_norailtie.yml", "rvm.env", ".git/**", "test/**"]
    set :creator, "devops@moxiesoft.com"
    set :description, "#{application} release - #{branch} #{full_date}"
    set :bucket, "spaces-releases"
    set :build_tasks, []

    set :binary_base, "#{application}/main/binary-#{arch}"
    set :binary_dir, "#{dist_dir}/#{binary_base}"
    set :package_base, "pool/#{application}/#{branch}"
    set :package_dir, "#{dist_dir}/#{package_base}"
    set :index_base, "#{application}/indexes"
    set :index_dir, "#{dist_dir}/#{index_base}"
    
    
    

    desc "get a tag or branch"
    task :get_code do
      git_branch,git_remote=capture("git ls-remote #{repository} #{branch}").split()
      run "if [ ! -d #{release_path} ];then git clone -q #{repository} #{release_path};cd #{release_path};git checkout #{git_branch} -q -b #{branch} ;fi"
      run "cd #{release_path}; git pull origin #{git_remote} -q; git reset --hard #{git_branch};git submodule -q init  && git submodule -q update "
      run "cd #{release_path} && bundle install --without development test"
    end



    desc "package the build"
    task :package_build do
      
      fpm=capture "which fpm" rescue nil
      run "gem install fpm --no-rdoc --no-ri" if fpm.nil?
      run "if [ ! -d #{package_dir} ]; then sudo mkdir -p #{package_dir} && sudo chown #{user}:#{user} #{package_dir};fi"
      set :package_name, "#{application}-#{branch}-#{full_date}.deb"
      
      ignore=fpm_ignore.map{|a| "-x '**/#{a}'"}.join(', ')
      
      puts "if [ ! -f #{package_dir}/#{package_name} ];then fpm -t deb -s dir -a #{arch} -n #{application} -v #{branch} --iteration #{full_date} -p #{package_dir}/#{package_name} #{ignore} -m #{fpm_creator} --description '#{description}' #{release_path}; fi"
    end

    task :update_repo do
      s3cmd=capture('which s3cmd')
      sudo "apt-get -y install s3cmd" if s3cmd.empty?
      run "cd #{dist_dir}/#{application};s3cmd sync s3://#{bucket}/dists/#{application}/ ."
      run "cd #{package_dir};s3cmd sync s3://#{bucket}/dists/#{package_base}/ ."
      count = fetch(:keep_releases, 5).to_i
      releases = capture("ls -xt #{package_dir}").split.reverse
      d = (releases - releases.last(count)).map{ |r| File.join(package_dir, r )}.join(" ")
      try_sudo "rm #{d}" unless d.empty?
      run "cd /mnt/builds/;dpkg-scanpackages -m dists/#{package_base} /dev/null > #{index_dir}/#{branch}"
      run "s3cmd sync #{package_dir}/* s3://#{bucket}/dists/#{package_base}/ --delete-removed"
      packages_file
    end



    task :packages_file do  
      run "cat #{index_dir}/* |gzip -c9 > #{binary_dir}/Packages.gz"
      run "s3cmd sync #{dist_dir}/#{application}/* s3://#{bucket}/dists/#{application}/"
    end

    desc "clean up a packaged build"
    task :clean_package_build do
      
      run "rm -rf #{package_dir}/#{branch}"
      run "rm -rf #{index_dir}/#{branch}"
      run "s3cmd del s3://#{bucket}/dists/#{package_base}/ --recursive"
      run "s3cmd del s3://#{bucket}/dists/#{index_base}/#{branch}"
      packages_file
    end

    before :build

    desc "build release"
    task :default do
      get_code
      deploy.create_symlink
      sn.write_version
      sn.write_mongo_config
      sn.rake_before_assets_build
      sn.build_assets
      package_build
      update_repo
    end


  end