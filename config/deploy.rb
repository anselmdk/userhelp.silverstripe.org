set :application, "userhelp.silverstripe.org"
set :repository,  "git://github.com/silverstripe/userhelp.silverstripe.org.git"
set :scm, :git
set :branch, "master"
set :use_sudo, false
set :current_dir, 'www'
set :deploy_via, :remote_cache
set :shared_children, %w(assets src .lucene-index)
set :keep_releases, 5
set :copy_exclude, ["config/*", "Capfile", "README.md"]

after "deploy:finalize_update", "composer:install"
# after "deploy:finalize_update", "deploy:copy_silverstripe_config"
# Before the switching the current symlink, do the silverstripe specifics
after "deploy:finalize_update", "deploy:symlink_custom_folders"
after "deploy:finalize_update", "deploy:silverstripe"
# after "deploy:setup", "deploy:fix_permissions"
before "composer:install", "composer:copy_vendors"

# Override the default capistrano deploy recipe that is build for rails apps
namespace :deploy do
	# The migrate task takes care of Silverstripe specifics
	#	1) Create a silverstripe-cache in the release folder
	#	2) Set 775 permissions on all folder
	#	3) Set 664 permissions on all files
	#	4) Change the owner of everything to the 'webserver_group'
	task :silverstripe do
		# Disabled the uploading of the _ss_environment.php, but leaving it here as an example
		# top.upload "./config/_ss_environment.php", "#{latest_release}/_ss_environment.php", :via => :scp

		# Add the cache folder inside this release so we don't need to worry about the cache being weird.
		run "mkdir -m 775 -p #{latest_release}/silverstripe-cache"

		# Make sure that framework/sake is executable
		run "chmod a+x #{latest_release}/framework/sake"

		# Run the mighty dev/build
		run "#{latest_release}/framework/sake dev/build flush=all"

		# Set permissions for directories
		run "find #{latest_release} -not -group #{webserver_group} -not -perm 775 -type d -exec chmod 775 {} \\;"

		# Set permissions for files
		run "find #{latest_release} -not -group #{webserver_group} -not -perm 664 -type f -exec chmod 664 {} \\;"

		# Set the execute permissions on framework/sake again
		run "chmod a+x #{latest_release}/framework/sake"

		# Set the group owner to the webserver group
		run "chown -RP :#{webserver_group} #{latest_release}"

		# Fix Lucene permissions
		run "if [ -d #{latest_release}/.lucene-index ]; then chown -RP :#{webserver_group} #{latest_release}/.lucene-index; fi"
		run "if [ -d #{latest_release}/.lucene-index ]; then chmod g+rwx #{latest_release}/.lucene-index; fi"
	end

	# Since the deploy_to dir is also the user's home folder,
	# we need to revert the group-writeable home folder which is configured by Cap.
	# Otherwise SSH prevents logins.
	task :fix_permissions do
		run "chmod g-w #{deploy_to}"	
	end

	task :copy_silverstripe_config do
		stages.each do |name|
			run "cp #{latest_release}/config/yml/#{name}.yml #{latest_release}/mysite/_config/environment.yml"
		end
	end

	# For some strange reason shared_children is not respected
	task :symlink_custom_folders do
		run "ln -nfs #{shared_path}/src #{release_path}/src"
		run "ln -nfs #{shared_path}/assets #{release_path}/assets"
		run "ln -nfs #{shared_path}/.lucene-index #{release_path}/.lucene-index"
	end	

end

namespace :composer do
	desc "Copy vendors from previous release"
	task :copy_vendors, :except => { :no_release => true } do
		run "if [ -d #{previous_release}/vendor ]; then cp -a #{previous_release}/vendor #{latest_release}/vendor; fi"
		run "if [ -d #{previous_release}/framework ]; then cp -a #{previous_release}/framework #{latest_release}/framework; fi"
	end
	task :install do
		run "sh -c 'cd #{latest_release} && curl -s http://getcomposer.org/installer | php'"
		run "sh -c 'cd #{release_path} && ./composer.phar selfupdate && ./composer.phar install --prefer-dist'"
	end
end