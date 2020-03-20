require 'cadence/workflow/executor'
require 'cadence/workflow/history'
require 'cadence/workflow/serializer'

module Cadence
  class Workflow
    class DecisionTaskProcessor
      def initialize(task, workflow_lookup, client)
        @task = task
        @task_token = task.taskToken
        @workflow_name = task.workflowType.name
        @workflow_class = workflow_lookup.find(workflow_name)
        @client = client
      end

      def process
        Cadence.logger.info("Processing a decision task for #{workflow_name}")

        unless workflow_class
          fail_task('Workflow does not exist')
          return
        end

        history = Workflow::History.new(task.history.events)
        # TODO: For sticky workflows we need to cache the Executor instance
        executor = Workflow::Executor.new(workflow_class, history)
        decisions = executor.run

        complete_task(decisions)
      rescue StandardError => error
        Cadence.logger.error("Decison task for #{workflow_name} failed with: #{error.inspect}")
        Cadence.logger.debug(error.backtrace.join("\n"))
      end

      private

      attr_reader :task, :task_token, :workflow_name, :workflow_class, :client

      def serialize_decisions(decisions)
        decisions.map { |(_, decision)| Workflow::Serializer.serialize(decision) }
      end

      def complete_task(decisions)
        Cadence.logger.info("Decision task for #{workflow_name} completed")

        client.respond_decision_task_completed(
          task_token: task_token,
          decisions: serialize_decisions(decisions)
        )
      end

      def fail_task(message)
        Cadence.logger.error("Decision task for #{workflow_name} failed with: #{message}")

        client.respond_decision_task_failed(
          task_token: task_token,
          cause: CadenceThrift::DecisionTaskFailedCause::UNHANDLED_DECISION,
          details: { message: message }
        )
      end
    end
  end
end