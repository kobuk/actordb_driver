% This Source Code Form is subject to the terms of the Mozilla Public
% License, v. 2.0. If a copy of the MPL was not distributed with this
% file, You can obtain one at http://mozilla.org/MPL/2.0/.
-module(actordb_driver).

-export([init/1,noop/1,
		open/1,open/2,open/3,open/4,
		exec_script/2,exec_script/3,exec_script/6,exec_script/4,exec_script/7,
		exec_read/2,exec_read/3,exec_read/4,
		exec_read_async/2,exec_read_async/3,
		exec_script_async/2,exec_script_async/3,exec_script_async/5,exec_script_async/6,
		store_prepared_table/2,
		close/1,inject_page/3,
		parse_helper/1,parse_helper/2, iterate_db/2,iterate_db/3,page_size/0,
		replication_done/1,file_write/3,
		lz4_compress/1,lz4_decompress/2,lz4_decompress/3,
		iterate_close/1, fsync_num/1,fsync/1,fsync/0,
		replicate_opts/2,replicate_opts/3,tcp_connect/4,all_tunnel_call/1,all_tunnel_call/2,checkpoint_lock/2,
		checkpoint/2, term_store/3,term_store/4, actor_info/2, wal_rewind/2,wal_rewind/3,
		tcp_connect_async/4,tcp_connect_async/5,tcp_reconnect/0, stmt_info/2]).

% #{paths => {Path1,Path2,...}, staticsqls => {StaticSql1,StaticSql2,...}, 
%   dbsize => MaxDbSize, rthreads => NumReadThreads, wthreads => NumWriteThreads}
init(Info) when is_map(Info) ->
	actordb_driver_nif:init(Info).

file_write(Offset,Items,L) ->
	actordb_driver_nif:file_write(Offset,Items,L).

open(Filename) ->
	open(Filename,0,wal).
open(Filename,ThreadNumber) ->
	open(Filename,ThreadNumber,wal).
open(Filename,ThreadNumber,Mode) when Mode == wal; Mode == blob ->
	Ref = make_ref(),
	ok = actordb_driver_nif:open(Ref, self(), Filename,ThreadNumber,Mode),
	case receive_answer(Ref) of
		{ok,Connection} ->
			{ok, {actordb_driver, make_ref(),Connection}};
		{error, _Msg}=Error ->
			Error
	end;
open(Filename,ThreadNumber,Sql) when is_binary(Sql); is_list(Sql) ->
	open(Filename,ThreadNumber,Sql,wal).
open(Filename,ThreadNumber,Sql,Mode) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:open(Ref, self(), Filename,ThreadNumber,Mode,Sql),
	case receive_answer(Ref) of
		{ok,Connection,Res} ->
			{ok, {actordb_driver, make_ref(),Connection},Res};
		{ok,Connection} ->
			{ok, {actordb_driver, make_ref(),Connection}};
		{error, _Msg}=Error ->
			Error
	end.

actor_info(Name,Thread) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:actor_info(Ref,self(),Name,Thread),
	receive_answer(Ref).

term_store({actordb_driver, _Ref, Connection},CurrentTerm,VotedFor) ->
	ok = actordb_driver_nif:term_store(Connection, CurrentTerm, VotedFor).
term_store(Name, CurrentTerm, VotedFor, Thread) ->
	ok = actordb_driver_nif:term_store(Name, CurrentTerm, VotedFor, Thread).

close({actordb_driver, _Ref, _Connection}) ->
	% Noop. Rely on GC. This is to avoid double closing.
	ok.

store_prepared_table(Indexes,Sqls) when is_tuple(Indexes), is_tuple(Sqls), tuple_size(Indexes) == tuple_size(Sqls) ->
	actordb_driver_nif:store_prepared_table(Indexes,Sqls).

checkpoint({actordb_driver, _Ref, Connection}, Evnum) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:checkpoint(Connection,Ref,self(),Evnum),
	receive_answer(Ref).

stmt_info({actordb_driver, _Ref, Connection}, Sql) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:stmt_info(Connection,Ref,self(),Sql),
	receive_answer(Ref).

parse_helper(Bin) ->
	parse_helper(Bin,0).
parse_helper(Bin,Offset) ->
	actordb_driver_nif:parse_helper(Bin,Offset).

replicate_opts(Con,PacketPrefix) ->
	replicate_opts(Con,PacketPrefix,1).
replicate_opts({actordb_driver, _Ref, Connection},PacketPrefix,Type) ->
	ok = actordb_driver_nif:replicate_opts(Connection,PacketPrefix,Type).

replication_done({actordb_driver, _Ref, Connection}) ->
	ok = actordb_driver_nif:replication_done(Connection).

tcp_connect(Ip,Port,ConnectStr,ConnNumber) ->
	Ref = make_ref(),
	actordb_driver_nif:tcp_connect(Ref,self(),Ip,Port,ConnectStr,ConnNumber),
	receive_answer(Ref).
tcp_connect_async(Ip,Port,ConnectStr,ConnNumber) ->
	Ref = make_ref(),
	actordb_driver_nif:tcp_connect(Ref,self(),Ip,Port,ConnectStr,ConnNumber),
	Ref.
tcp_connect_async(Ip,Port,ConnectStr,ConnNumber,Type) ->
	Ref = make_ref(),
	actordb_driver_nif:tcp_connect(Ref,self(),Ip,Port,ConnectStr,ConnNumber,Type),
	Ref.
tcp_reconnect() ->
	actordb_driver_nif:tcp_reconnect().

all_tunnel_call(Bin) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:all_tunnel_call(Ref,self(),Bin),
	receive_answer(Ref).

all_tunnel_call(Head,Body) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:all_tunnel_call(Ref,self(),Head,Body),
	receive_answer(Ref).

lz4_compress(B) ->
	actordb_driver_nif:lz4_compress(B).
lz4_decompress(B,SizeOrig) ->
	actordb_driver_nif:lz4_decompress(B,SizeOrig).
lz4_decompress(B,SizeOrig,SizeIn) ->
	actordb_driver_nif:lz4_decompress(B,SizeOrig,SizeIn).

% wal_pages({actordb_driver, _Ref, Connection}) ->
%     actordb_driver_nif:wal_pages(Connection).

wal_rewind({actordb_driver, _Ref, Connection},Evnum) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:wal_rewind(Connection, Ref, self(),Evnum),
	receive_answer(Ref).
wal_rewind({actordb_driver, _Ref, Connection}, 0, ReplaceSql) when is_binary(ReplaceSql); is_list(ReplaceSql) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:wal_rewind(Connection, Ref, self(),0, ReplaceSql),
	receive_answer(Ref).

fsync_num({actordb_driver, _Ref, Connection}) ->
	actordb_driver_nif:fsync_num(Connection).
fsync() ->
	ok = actordb_driver_nif:fsync().
fsync({actordb_driver, _Ref, Connection} = C) ->
	Ref = make_ref(),
	case actordb_driver_nif:fsync(Connection, Ref, self()) of
		again ->
			timer:sleep(10),
			fsync(C);
		ok ->
			% receive_answer(Ref)
			ok
	end.

iterate_close({iter,Iter}) ->
	ok = actordb_driver_nif:iterate_close(Iter).

iterate_db({actordb_driver, _Ref, Connection},{iter,Iter}) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:iterate_db(Connection, Ref, self(),Iter),
	receive_answer(Ref).
iterate_db({actordb_driver, _Ref, Connection},Evterm,Evnum) when is_integer(Evnum) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:iterate_db(Connection, Ref, self(), Evterm,Evnum),
	receive_answer(Ref).

inject_page({actordb_driver, _Ref, Connection},Bin,Head) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:inject_page(Connection, Ref, self(),Bin,Head),
	receive_answer(Ref).
% inject_page({actordb_driver, _Ref, Connection},Bin,Head) ->
% 	Ref = make_ref(),
% 	ok = actordb_driver_nif:inject_page(Connection, Ref, self(),Bin,Head),
% 	receive_answer(Ref).

page_size() ->
	actordb_driver_nif:page_size().

noop({actordb_driver, _Ref, Connection}) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:noop(Connection, Ref, self()),
	receive_answer(Ref).

exec_read(Sql,Db) ->
	exec_read(Sql,Db,infinity).
exec_read(Sql,{actordb_driver, _Ref, Connection},Timeout) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_read(Connection, Ref, self(), Sql),
	receive_answer(Ref,Connection,Timeout);
exec_read(Sql,Recs,{actordb_driver, _Ref, _Connection} = Db) ->
	exec_read(Sql,Recs,Db,infinity).
exec_read(Sql,Recs,{actordb_driver, _Ref, Connection},Timeout) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_read(Connection, Ref, self(), Sql, Recs),
	receive_answer(Ref,Connection,Timeout).

exec_script(Sql, Db) ->
	exec_script(Sql,Db,infinity,0,0,<<>>).

exec_script(Sql,Recs, Db) when element(1,Db) == actordb_driver ->
	exec_script(Sql,Recs,Db,infinity,0,0,<<>>);
exec_script(Sql, Db, Timeout) when element(1,Db) == actordb_driver ->
	exec_script(Sql,Db,Timeout,0,0,<<>>).

exec_script(Sql, Recs, Db, Timeout) when is_integer(Timeout), element(1,Db) == actordb_driver ->
	exec_script(Sql,Recs,Db,Timeout,0,0,<<>>).

exec_script(Sql, {actordb_driver, _Ref, Connection},Timeout,Term,Index,AppendParam) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_script(Connection, Ref, self(), Sql,Term,Index,AppendParam),
	receive_answer(Ref,Connection,Timeout).
exec_script(Sql, Recs, {actordb_driver, _Ref, Connection},Timeout,Term,Index,AppendParam) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_script(Connection, Ref, self(), Sql,Term,Index,AppendParam,Recs),
	receive_answer(Ref,Connection,Timeout).


exec_read_async(Sql,{actordb_driver, _Ref, Connection}) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_read(Connection, Ref, self(), Sql),
	Ref.
exec_read_async(Sql,Recs,{actordb_driver, _Ref, Connection}) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_read(Connection, Ref, self(), Sql, Recs),
	Ref.

exec_script_async(Sql,Recs, Db) when element(1,Db) == actordb_driver ->
	exec_script_async(Sql,Recs,Db,0,0,<<>>).
exec_script_async(Sql, Db) when element(1,Db) == actordb_driver ->
	exec_script_async(Sql,Db,0,0,<<>>).

exec_script_async(Sql, {actordb_driver, _Ref, Connection},Term,Index,AppendParam) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_script(Connection, Ref, self(), Sql,Term,Index,AppendParam),
	Ref.
exec_script_async(Sql, Recs, {actordb_driver, _Ref, Connection},Term,Index,AppendParam) ->
	Ref = make_ref(),
	ok = actordb_driver_nif:exec_script(Connection, Ref, self(), Sql,Term,Index,AppendParam,Recs),
	Ref.

checkpoint_lock({actordb_driver, _Ref, Connection},Lock) ->
	case Lock of
		true ->
			L = 1;
		false ->
			L = 0;
		0 = L ->
			ok;
		1 = L ->
			ok
	end,
	Ref = make_ref(),
	ok = actordb_driver_nif:checkpoint_lock(Connection,Ref,self(),L).

% backup_init({actordb_driver, _, Dest},{actordb_driver, _, Src}) ->
%     Ref = make_ref(),
%     ok = actordb_driver_nif:backup_init(Dest,Src,Ref,self()),
%     case receive_answer(Ref) of
%         {ok,B} ->
%             {ok,{backup,make_ref(),B}};
%         error ->
%             error
%     end.

% backup_step({backup, _Ref, B},N) ->
%     Ref = make_ref(),
%     ok = actordb_driver_nif:backup_step(B,Ref,self(),N),
%     receive_answer(Ref).

% backup_finish({backup, _Ref, B}) ->
%     Ref = make_ref(),
%     ok = actordb_driver_nif:backup_finish(B,Ref,self()),
%     receive_answer(Ref).

% backup_pages({backup, _Ref, B}) ->
%     actordb_driver_nif:backup_pages(B).


receive_answer(Ref) ->
	receive
		{Ref, Resp} -> Resp
	end.
receive_answer(Ref,Connection,Timeout) ->
	receive
		{Ref,Resp} ->
			Resp
	after Timeout ->
		ok = actordb_driver_nif:interrupt_query(Connection),
		receive
			{Ref,Resp} ->
				Resp
		end
   end.
