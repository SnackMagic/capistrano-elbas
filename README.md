*Versions < 3 of ELBAS are no longer being maintained. I will only be maintaining the current feature-set which relies on Launch Templates and AWS SDK v3.*

# Capistrano ELBAS (Elastic Load Balancer & AutoScaling)

[![Gem Version](https://badge.fury.io/rb/elbas.svg)](https://badge.fury.io/rb/elbas)

ELBAS was written to ease the deployment of Rails applications to AWS AutoScale
groups. During your Capistrano deployment, ELBAS will:

- Deploy your code to each running instance connected to a given AutoScale group
- After deployment, create an AMI from one of the running instances
- Update the AutoScale group's launch template with the AMI ID and default version to latest
- Delete any outdated AMIs created by previous ELBAS deployments

## Installation

Add to Gemfile, then `bundle`:

`gem 'elbas'`

Add to Capfile:

`require 'elbas/capistrano'`

## Configuration

Setup AWS credentials:

```ruby
set :aws_access_key, ENV['AWS_ACCESS_KEY_ID']
set :aws_secret_key, ENV['AWS_SECRET_ACCESS_KEY']
set :aws_region,     ENV['AWS_REGION']
```

Set the means through which to communicate with instances. Select from `public_dns_name` *(the default)*, `public_ip_address`, `private_dns_name` and `private_ip_address`. For example, if you are using a bastion host and SSHing into your instances via a private subnet you would want to add the following:

```ruby
set :elbas_hostname_type, 'private_ip_address'
```

Define how many past AMIs to keep during cleanup. The default is 5.

```ruby
set :elbas_keep_amis, 5
```

Define whether the AMI should be created with `no_reboot` enabled. The default is `true` such that the instance is not rebooted when creating the image. However, AWS recommends `no_reboot = false` in order to guarantee the file system integrity of the created image.

```ruby
set :elbas_no_reboot_on_ami_creation, false
```

If you set `elbas_no_reboot_on_ami_creation = true` then you may want to instruct your OS to flush all filesystem changes to disk before creating the AMI.

```ruby
set :elbas_sync_and_wait, true        # Default: false
set :elbas_sync_and_wait_cmd, 'sync'  # Default: sync
set :elbas_sync_and_wait_delay, 5     # Default: 5 seconds
set :sync_and_wait_as_sudo, false     # Default: true
```

## Usage

Instead of using Capistrano's `server` method, use `autoscale` instead in
`deploy/<environment>.rb` (replace <environment> with your environment). Provide
the name of your AutoScale group instead of a hostname:

```ruby
autoscale 'my-autoscale-group', user: 'apps', roles: [:app, :web, :db]
```

If you have multiple autoscaling groups to deploy to, specify each of them:

```ruby
autoscale 'app-autoscale-group', user: 'apps', roles: [:app, :web]
autoscale 'worker-autoscale-group', user: 'apps', roles: [:worker]
```

Run `cap production deploy`.

**As of version 3, your AWS setup must use launch templates as opposed to launch
configurations.** This allows ELBAS to simply create a new launch template version
with the new AMI ID after a deployment. It no longer needs to update your
AutoScale group or mess around with network settings, instance sizes, etc., as
that information is all contained within the launch template. Failure to use a
launch template will result in a `Elbas::Errors::NoLaunchTemplate` error.

### Customizing Server Properties

You can pass a block to `autoscale` and return properties for any specific server.
The block accepts the server and the server's index as arguments.

For example, if you want to apply the `:db` role to only the first server:

```ruby
autoscale 'my-autoscale-group', roles: [:app, :web] do |server, i|
  { roles: [:app, :web, :db] } if i == 0
end
```

Returning `nil` from this block will cause the server to use the properties
passed to `autoscale`.

Returning anything but `nil` will override the entire properties hash (as
opposed to merging the two hashes together).

### Listing Servers

You may need to SSH into your servers while debugging deployed code, and
not everyone has a jumpbox on a basic AutoScaling setup. ELBAS provides a command
that will list the `ssh` command necessary to connect to each server in any given
environment:

```
cap production elbas:ssh
```

Output will be something like:

```
[ELBAS] Adding server: ec2-12-34-567-890.compute-1.amazonaws.com
[ELBAS] SSH commands:
[ELBAS]     1) ssh deploy@ec2-12-34-567-890.compute-1.amazonaws.com
```
