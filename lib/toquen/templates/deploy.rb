# Set your AWS access key id and secret.  This should be provisioned in
# Amazon AWS if you haven't already set it up.
set :aws_access_key_id, ""
set :aws_secret_access_key, ""

# Set the location of your SSH key.  You can give a list of files, but
# the first key given will be the one used to upload your chef files to
# each server.
set :ssh_options, { :keys => ["./mykey.pem"], :user => "ubuntu" }

# Set the location of your cookbooks/data bags/roles for Chef
set :chef_cookbooks_path, 'kitchen/cookbooks'
set :chef_data_bags_path, 'kitchen/data_bags'
set :chef_roles_path, 'kitchen/roles'

# This is the version of rubygems installed (for Chef)
set :rubygems_version, "2.1.11"
