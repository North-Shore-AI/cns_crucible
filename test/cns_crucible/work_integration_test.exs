defmodule CnsCrucible.WorkIntegrationTest do
  use ExUnit.Case, async: false

  alias CnsCrucible.WorkIntegration
  alias Work.Registry

  setup do
    # Ensure Work application is started
    {:ok, _} = Application.ensure_all_started(:work)

    # Clear registry before each test
    if Process.whereis(Registry) do
      :ets.delete_all_objects(:work_registry)
    end

    :ok
  end

  describe "submit_proposer_stage/2" do
    test "submits a Proposer experiment to Work" do
      experiment = %{
        id: Ecto.UUID.generate(),
        name: "test_proposer",
        type: :proposer
      }

      assert {:ok, job_id} = WorkIntegration.submit_proposer_stage(experiment)
      assert is_binary(job_id)

      # Verify job was created
      assert {:ok, job} = Work.get(job_id)
      assert job.kind == :experiment_step
      assert job.tenant_id == "cns_crucible"
      assert job.namespace == "proposer"
      assert job.metadata.source == :cns_crucible
      assert job.metadata.experiment_type == :proposer
    end

    test "accepts custom options" do
      experiment = %{
        id: Ecto.UUID.generate(),
        name: "test_proposer_custom"
      }

      assert {:ok, job_id} =
               WorkIntegration.submit_proposer_stage(experiment,
                 priority: :batch,
                 gpu: "A100",
                 memory_mb: 8192,
                 timeout_ms: 1_800_000
               )

      assert {:ok, job} = Work.get(job_id)
      assert job.priority == :batch
      assert job.resources.gpu == "A100"
      assert job.resources.memory_mb == 8192
      assert %DateTime{} = job.constraints.deadline
      assert job.constraints.retry_policy.max_attempts == 1
    end
  end

  describe "submit_antagonist_stage/2" do
    test "submits an Antagonist experiment to Work" do
      experiment = %{
        id: Ecto.UUID.generate(),
        name: "test_antagonist",
        type: :antagonist
      }

      assert {:ok, job_id} = WorkIntegration.submit_antagonist_stage(experiment)
      assert is_binary(job_id)

      assert {:ok, job} = Work.get(job_id)
      assert job.kind == :experiment_step
      assert job.namespace == "antagonist"
      assert job.metadata.experiment_type == :antagonist
    end
  end

  describe "submit_synthesizer_stage/2" do
    test "submits a Synthesizer experiment to Work" do
      experiment = %{
        id: Ecto.UUID.generate(),
        name: "test_synthesizer",
        type: :synthesizer
      }

      assert {:ok, job_id} = WorkIntegration.submit_synthesizer_stage(experiment)
      assert is_binary(job_id)

      assert {:ok, job} = Work.get(job_id)
      assert job.kind == :experiment_step
      assert job.namespace == "synthesizer"
      assert job.metadata.experiment_type == :synthesizer
    end
  end

  describe "submit_training/2" do
    test "submits a training job with default options" do
      config = %{
        model_type: "proposer",
        dataset: "scifact",
        epochs: 3
      }

      assert {:ok, job_id} = WorkIntegration.submit_training(config)
      assert is_binary(job_id)

      assert {:ok, job} = Work.get(job_id)
      assert job.kind == :training_step
      assert job.priority == :batch
      assert job.namespace == "training"
      assert job.resources.gpu == "A100"
      assert job.resources.memory_mb == 16_384
      assert job.payload == config
    end

    test "submits a training job with custom options" do
      config = %{
        model_type: "synthesizer",
        dataset: "fever"
      }

      assert {:ok, job_id} =
               WorkIntegration.submit_training(config,
                 priority: :offline,
                 gpu: "V100",
                 memory_mb: 32_768,
                 timeout_ms: 7_200_000,
                 max_retries: 3
               )

      assert {:ok, job} = Work.get(job_id)
      assert job.priority == :offline
      assert job.resources.gpu == "V100"
      assert job.resources.memory_mb == 32_768
      assert %DateTime{} = job.constraints.deadline
      assert job.constraints.retry_policy.max_attempts == 3
    end
  end

  describe "get_job_status/1" do
    test "retrieves job status" do
      experiment = %{
        id: Ecto.UUID.generate(),
        name: "test_status"
      }

      assert {:ok, job_id} = WorkIntegration.submit_proposer_stage(experiment)
      assert {:ok, job} = WorkIntegration.get_job_status(job_id)
      assert job.status in [:pending, :queued, :running, :succeeded, :failed]
    end

    test "returns error for non-existent job" do
      assert {:error, :not_found} = WorkIntegration.get_job_status("nonexistent")
    end
  end

  describe "list_jobs/1" do
    test "lists jobs for CNS Crucible tenant" do
      # Submit a few jobs
      experiment1 = %{id: Ecto.UUID.generate(), name: "test1"}
      experiment2 = %{id: Ecto.UUID.generate(), name: "test2"}

      {:ok, _job_id1} = WorkIntegration.submit_proposer_stage(experiment1)
      {:ok, _job_id2} = WorkIntegration.submit_antagonist_stage(experiment2)

      jobs = WorkIntegration.list_jobs()
      assert length(jobs) >= 2
      assert Enum.all?(jobs, &(&1.tenant_id == "cns_crucible"))
    end

    test "filters jobs by namespace" do
      experiment = %{id: Ecto.UUID.generate(), name: "test"}
      {:ok, _job_id} = WorkIntegration.submit_proposer_stage(experiment)

      jobs = WorkIntegration.list_jobs(namespace: "proposer")

      # credo:disable-for-next-line Credo.Check.Warning.ExpensiveEmptyEnumCheck\n      assert length(jobs) >= 1
      assert Enum.all?(jobs, &(&1.namespace == "proposer"))
    end
  end

  describe "get_stats/0" do
    test "returns Work statistics" do
      stats = WorkIntegration.get_stats()
      assert Map.has_key?(stats, :scheduler)
      assert Map.has_key?(stats, :registry)
    end
  end

  # Note: await_job/2 tests are omitted because they require actual job execution
  # which would need the Work executor to be running and a proper backend configured.
  # In a real integration test suite, you would:
  # 1. Start the Work executor
  # 2. Configure a mock or local backend
  # 3. Submit and await jobs
  # 4. Verify results
end
