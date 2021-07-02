require_relative 'ractor_server'
require_relative 'fiber_server'
require_relative 'single_threaded_server'
require_relative 'multi_threaded_server'

require_relative 'apps/file_serving_app'
require_relative 'apps/cpu_heavy_app'
require_relative 'apps/web_request_app'

APP = CpuHeavyApp
# APP = FileServingApp
# APP = WebRequestApp

# SERVER = FiberServer
SERVER = SingleThreadedServer
# SERVER = MultiThreadedServer
# SERVER = RactorServer

SERVER.new(APP.new).start
