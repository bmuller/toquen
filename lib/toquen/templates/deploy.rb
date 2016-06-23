# Set your AWS access key id and secret.  This should be provisioned in
# Amazon AWS if you haven't already set it up.  Leave these as nil if
# you already have your credentials set in ~/.aws/credentials
set :aws_access_key_id, nil
set :aws_secret_access_key, nil

# Set the location of your SSH key.  You can give a list of files, but
# the first key given will be the one used to upload your chef files to
# each server.
set :ssh_options, { :keys => ["./mykey.pem"], :user => "ubuntu" }

# Set the location of your cookbooks/data bags/roles for Chef
set :chef_cookbooks_path, 'kitchen/cookbooks'
set :chef_data_bags_path, 'kitchen/data_bags'
set :chef_roles_path, 'kitchen/roles'

# this directory should exist, even if empty
set :chef_environments_path, 'kitchen/environment'
