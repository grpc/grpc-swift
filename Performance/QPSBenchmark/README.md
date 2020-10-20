#  QPS Benchmark worker

An implementation of the QPS worker for benchmarking described in the  
[gRPC benchmarking guide](https://grpc.io/docs/guides/benchmarking/)

## Building
To rebuild the proto files run `make generate-qps-worker`.

The benchmarks can be built in the usual SPM way but release mode is strongly recommended - `swift build -c release`

## Running the benchmarks

To date the changes to gRPC to run the tests automatically have not been pushed upstream.

You can easily run the tests locally using the C++ driver program from gRPC - note this is built as a side effect 
of running the C++ tests which can be done in a gRPC checkout with 
`./tools/run_tests/run_performance_tests.py -l c++ -r cpp_protobuf_async_unary_qps_unconstrained_insecure`

For an example of running a benchmarking tests proceed as follows
1. Open a terminal window and run the QPSBenchmark - `swift run -c release QPSBenchmark --driver_port 10400`.  
This will become the server when instructed by the driver.
2. Open another terminal window and run QPSBenchmark - `swift run -c release QPSBenchmark --driver_port 10410`.
This will become the client when instructed by the driver.
3. Use the driver to control the test.  In your checkout of [gRPC](https://github.com/grpc/grpc) 
configure the environment with `export QPS_WORKERS="localhost:10400,localhost:10410"` then run
`cmake/build/qps_json_driver '--scenarios_json={"scenarios": [{"name": "swift_protobuf_async_unary_qps_unconstrained_insecure", "warmup_seconds": 5, "benchmark_seconds": 30, "num_servers": 1, "server_config": {"async_server_threads": 0, "channel_args": [{"str_value": "throughput", "name": "grpc.optimization_target"}], "server_type": "ASYNC_SERVER", "security_params": null, "threads_per_cq": 0, "server_processes": 0}, "client_config": {"security_params": null, "channel_args": [{"str_value": "throughput", "name": "grpc.optimization_target"}], "async_client_threads": 0, "outstanding_rpcs_per_channel": 100, "rpc_type": "UNARY", "payload_config": {"simple_params": {"resp_size": 0, "req_size": 0}}, "client_channels": 64, "threads_per_cq": 0, "load_params": {"closed_loop": {}}, "client_type": "ASYNC_CLIENT", "histogram_params": {"max_possible": 60000000000.0, "resolution": 0.01}, "client_processes": 0}, "num_clients": 0}]}' --scenario_result_file=scenario_result.json`
This will run a test of asynchronous unary client and server, using all the cores on the machine.  
64 channels each with 100 outstanding requests.
