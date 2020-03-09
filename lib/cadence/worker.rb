require 'cadence/client'
require 'cadence/workflow/poller'
require 'cadence/activity/poller'
require 'cadence/execution_options'
require 'cadence/executable_lookup'

module Cadence
  class Worker
    def initialize
      @workflows = Hash.new { |hash, key| hash[key] = ExecutableLookup.new }
      @activities = Hash.new { |hash, key| hash[key] = ExecutableLookup.new }
      @pollers = []
      @shutting_down = false
    end

    def register_workflow(workflow_class, options = {})
      execution_options = ExecutionOptions.new(workflow_class, options)
      key = [execution_options.domain, execution_options.task_list]

      @workflows[key].add(execution_options.name, workflow_class)
    end

    def register_activity(activity_class, options = {})
      execution_options = ExecutionOptions.new(activity_class, options)
      key = [execution_options.domain, execution_options.task_list]

      @activities[key].add(execution_options.name, activity_class)
    end

    def start
      workflows.each_pair do |(domain, task_list), lookup|
        pollers << workflow_poller_for(domain, task_list, lookup)
      end

      activities.each_pair do |(domain, task_list), lookup|
        pollers << activity_poller_for(domain, task_list, lookup)
      end

      trap_signals

      pollers.each(&:start)

      # wait until instructed to shut down
      while !shutting_down? do
        sleep 1
      end
    end

    def stop
      @shutting_down = true
      pollers.each(&:stop)
      pollers.each(&:wait)
    end

    private

    attr_reader :activities, :workflows, :pollers

    def shutting_down?
      @shutting_down
    end

    def workflow_poller_for(domain, task_list, lookup)
      Workflow::Poller.new(domain, task_list, lookup.freeze)
    end

    def activity_poller_for(domain, task_list, lookup)
      Activity::Poller.new(domain, task_list, lookup.freeze)
    end

    def trap_signals
      %w[TERM INT].each do |signal|
        Signal.trap(signal) { stop }
      end
    end
  end
end