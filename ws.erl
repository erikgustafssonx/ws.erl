% Sources used
%Basic example of TCP-server used
%http://20bits.com/article/erlang-a-generalized-tcp-server
%String tutorial http://blog.dynamicprogrammer.com/2012/11/23/learning-erlang-9-string-manipulation-in-erlang.html
-module(ws).

-export([start/0,start/1]).
-compile(export_all).
-define(TCP_OPTIONS, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]).
% Generate users id on the form user[x][y]
makeuserid(AcceptCount) ->
	"user"++integer_to_list(AcceptCount).

timeAsString() ->
	% Getting current time as a string
	% Method found here http://stackoverflow.com/questions/7354840/retrieving-the-time-as-a-hhmmss-string
    {H, M, S} = time(),
    io_lib:format('~2..0b:~2..0b:~2..0b', [H, M, S]).

expandURL(Path) ->
	%io:format("checking path ~s",[Path]),
	case Path=:="/" of
		true ->
			%io:format("changing to index.html"),
			"/index.html";
		false ->
			%io:format("keeping"),
			Path
	end.

logProcess() ->
    receive
        {log,Message} ->
            file:write_file("log",Message++"\n",[append]),
            logProcess()
    end.
        
fileExtension(Filename) ->
	lists:last(string:tokens(Filename,".")).

start() -> 
	start(1024).

start(Port) ->
	LoggerPid=spawn(ws, logProcess,[]),
    {ok, LSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    acceptLoop(LSocket,LoggerPid,1).

% Wait for incoming connections and spawn the handleRequest when we get one.
acceptLoop(LSocket,LoggerPid,AcceptCount) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    spawn(fun() -> handleRequest(Socket,LoggerPid,AcceptCount) end),
    acceptLoop(LSocket,LoggerPid,AcceptCount+1).

parseClientHeader(ClientHeader) ->
	ClientHeaderLines=string:tokens(ClientHeader,"\n"),
	[FirstLine|ExtraLines] = ClientHeaderLines,
	[Method,RawPath,_]=string:tokens(FirstLine," "),
	RawExtraFields=lists:map(fun(Line) ->string:tokens(Line,":") end,ExtraLines),
	% Converting list to tuples
	% Method found here: %http://stackoverflow.com/questions/1822405/convert-nested-lists-into-a-list-of-tuples
	ExtraFields = [{K,V} || [K|[V|_]] <- RawExtraFields],
	FirstCookieValueRaw=case lists:keyfind("Cookie",1,ExtraFields) of 
		{Key,Value}->
			CookieList=string:tokens(Value,";"),
			FirstCookie=lists:nth(1,CookieList),
			lists:nth(2,string:tokens(FirstCookie,"="));
		_->
			""
	end,
	FirstCookieValue=lists:filter(fun(X) -> X/=13 end,FirstCookieValueRaw),%remove unwanted 13
	{Method,RawPath,FirstCookieValue}.
	

% Retrive http request and send back answer
handleRequest(Socket,LoggerPid,AcceptCount) ->
    {ok, BinClientHeader} = gen_tcp:recv(Socket, 0),
			HeaderStart = "HTTP/1.1 200 OK\n",
			HeaderEnd = "\n",
			ClientHeader = binary:bin_to_list(BinClientHeader),
			
			{Method,RawPath,FirstCookieValue}=parseClientHeader(ClientHeader),

			
			
			Path=expandURL(RawPath),
			{ok,Dir} = file:get_cwd(),
			Fullpath = Dir++"/"++"www"++Path,
			PathLen = length(Fullpath),
			
			%Mimetype list http://hul.harvard.edu/ois/systems/wax/wax-public-help/mimetypes.htm
			Extension = fileExtension(Path),
			case Extension of 
				"html" ->
					ContentType = "Content-Type: text/html; charset=utf-8\n";
				"css"->
					ContentType = "Content-type: text/css\n";
				_ ->
					ContentType="Content-Type: application/octet-stream\n"
			end,
			FileContent=case file:read_file(Fullpath) 	of
				{ok,ReadFileContent}->
					ReadFileContent;
				{error, enoent} ->
					"Error"
			end,
			LogMessage = timeAsString()++" "++FirstCookieValue++" visits page "++Path,
			case FirstCookieValue of
				"" ->
					HeaderCookie="Set-Cookie: userid="++makeuserid(AcceptCount)++"\n";
				Value ->
					HeaderCookie=""
			end,
			ServerHeader=HeaderStart++HeaderCookie++ContentType++HeaderEnd,

			% Print client and server header
			io:format("========\n~s\n\n~s~s\n",[LogMessage,ClientHeader,ServerHeader]),
			
			
			% Send log message to logger
			LoggerPid ! {log, LogMessage},
            
            % Send server header
            gen_tcp:send(Socket, ServerHeader),
            
            % Send content
            gen_tcp:send(Socket, FileContent),
            
            % Close socket
            gen_tcp:close(Socket).
