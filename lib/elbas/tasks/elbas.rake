require "elbas"
include Elbas::Logger

namespace :elbas do
  task :ssh do
    include Capistrano::DSL

    info "SSH commands:"
    env.servers.to_a.each.with_index do |server, i|
      info "    #{i + 1}) ssh #{fetch(:user)}@#{server.hostname}"
    end
  end

  task :deploy do
    fetch(:aws_autoscale_group_names).each do |aws_autoscale_group_name|
      info "Auto Scaling Group: #{aws_autoscale_group_name}"
      asg = Elbas::AWS::AutoscaleGroup.new aws_autoscale_group_name

      release_version = fetch(:elbas_release_version) || fetch(:current_revision) || `git rev-parse HEAD`.strip
      release_timestamp = fetch(:release_timestamp) || env.timestamp.strftime("%Y%m%d%H%M%S")
      no_reboot = fetch(:elbas_no_reboot_on_ami_creation, true)
      sync_and_wait = fetch(:elbas_sync_and_wait, false)

      if sync_and_wait
        sync_and_wait_cmd = fetch(:elbas_sync_and_wait_cmd, "sync")
        sync_and_wait_delay = fetch(:elbas_sync_and_wait_delay, 5)

        info "Calling #{sync_and_wait_cmd} and waiting #{sync_and_wait_delay} seconds..."
        on roles([:web, :app]) do
          sync_and_wait_as_sudo = fetch(:sync_and_wait_as_sudo, true)
          if sync_and_wait_as_sudo
            execute :sudo, sync_and_wait_cmd
          else
            execute sync_and_wait_cmd
          end
        end
        sleep sync_and_wait_delay
      end

      ami_instance = asg.instances.oldest
      info "Creating AMI from instance #{ami_instance.id} (no_reboot = #{no_reboot})..."
      ami = Elbas::AWS::AMI.create ami_instance, no_reboot
      info "Created AMI: #{ami.id}"

      info "Tagging AMI: Name = #{asg.name}"
      ami.tag "Name", asg.name

      info "Tagging AMI: ELBAS-Deploy-group = #{asg.name}"
      ami.tag "ELBAS-Deploy-group", asg.name

      info "Tagging AMI: ELBAS-Deploy-revision = #{release_version}"
      ami.tag "ELBAS-Deploy-revision", release_version

      info "Tagging AMI: ELBAS-Deploy-id = #{release_timestamp}"
      ami.tag "ELBAS-Deploy-id", release_timestamp

      launch_template = asg.launch_template
      info "Updating launch template #{launch_template.name} with the new AMI..."
      launch_template = launch_template.update ami
      info "Updated launch template, latest version = #{launch_template.version}"

      keep = fetch(:elbas_keep_amis) || 5
      info "Cleaning up old AMIs (keeping #{keep})..."

      ami_ancestors_count = ami.ancestors.count
      if ami_ancestors_count > keep
        to_remove = ami_ancestors_count - keep + 1

        amis = ami.ancestors.sort_by { |ancestor| ancestor.created_at }
        info "Existing AMIs: #{amis.map(&:id).join(", ")}"
        amis = amis.shift(to_remove)
        # amis = ami.ancestors.drop(keep)

        amis.each do |ancestor|
          info "Deleting AMI: #{ancestor.id}"
          ancestor.delete
        end
        info "Deleted #{amis.count} old AMIs and keeping newest #{keep}"
      else
        info "No old AMIs to delete"
      end
    end
    info "Deployment complete!"
  end

  task :list do
    fetch(:aws_autoscale_group_names).each do |aws_autoscale_group_name|
      on roles([:web, :app]) do
        info "Auto Scaling Group: #{aws_autoscale_group_name}"
        asg = Elbas::AWS::AutoscaleGroup.new aws_autoscale_group_name
      end
    end
  end
end
