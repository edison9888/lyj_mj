-module(server_frame).
-author('yh@gmail.com').
-export([start/0, stop/0]).

-spec start() -> ok | {error, term()}.
start() ->
	application:start(server_frame).

-spec stop() -> ok | {error, term()}.
stop() ->
	application:stop(server_frame).