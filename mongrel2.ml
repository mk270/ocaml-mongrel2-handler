
(*
  OCaml-Mongrel2-Handler, a Mongrel2 handler for OCaml

  Copyright (C) 2013  Martin Keegan

  This programme is free software; you may redistribute and/or modify
  it under the terms of the Apache License v2.0
*)

(* this code isn't even supposed to be alpha quality - it's just a hack ATM *)

open Printf
open Lwt
open Str
open Yojson.Safe

type http_req = {
	hr_uuid : string;
	hr_conn_id : int;
	hr_path : string;
	hr_headers : (string * string) list;
	hr_body : string;
}

let by_space = Str.regexp " "
let by_colon = Str.regexp ":"

let parse_netstring ns =
	let parse_well_formed len_s rest =
		let len = int_of_string len_s in
			assert (rest.[len] = ',');
			(String.sub rest 0 len,
			 String.sub rest (len + 1) (String.length rest - len - 1))
	in
	let words = Str.bounded_split by_colon ns 2 in
		match words with
			| [ len_s; rest; ] -> parse_well_formed len_s rest
			| _ -> assert false

let parse_headers hh =
	let get_string = function
		| key, `String s -> key, s
		| _ -> assert false
	in

	let tmp = Yojson.Safe.from_string hh in
		match tmp with
			| `Assoc kvps -> List.map get_string kvps
			| _ -> assert false

let parse resp =
	let parse_valid_payload uuid conn_id path rest =
		let conn_id = int_of_string conn_id in
		let headers, rest' = parse_netstring rest in
		let body, _ = parse_netstring rest' in
		let headers = parse_headers headers in
			{
				hr_uuid = uuid;
				hr_conn_id = conn_id;
				hr_path = path;
				hr_headers = headers;
				hr_body = body;
			}
	in
	let words = Str.bounded_split by_space resp 4 in
		match words with
			| [uuid; conn_id; path; rest] ->
				parse_valid_payload uuid conn_id path rest
			| _ -> assert false

let http_response body code status headers =
	let content_length = String.length body in
	let headers = ("Content-Length", string_of_int content_length) :: headers
	in
	let sep_by_colon kv =
		let k, v = kv in
			k ^ ": " ^ v
	in
	let headers' = String.concat "\r\n" (List.map sep_by_colon headers) in
		sprintf "HTTP/1.1 %d %s\r\n%s\r\n\r\n%s" code status headers' body

let send uuid conn_id msg =
	let len_s = String.length conn_id in
	let header = Printf.sprintf "%s %d:%s," uuid len_s conn_id in
		header ^ " " ^ msg

let deliver uuid idents data =
	let idents = List.map string_of_int idents in
		send uuid (String.concat " " idents) data

let handle_reply reply =
	let hreq = parse reply in
	let page_text = "<html> URI was:" ^
		(List.assoc "URI" hreq.hr_headers) ^
		"</html>"
	in
	let headers = [("Content-type", "text/html")] in
	let payload =
		http_response page_text 200 "OK" headers in
		deliver hreq.hr_uuid [hreq.hr_conn_id] payload

let handoff sock hres =
	Lwt_zmq.Socket.send sock hres >>=
		(fun () -> Lwt_io.printlf "resp: [%s]" hres)

let handle_recv sock () =
	Lwt_zmq.Socket.recv sock

let mongrel_handler socket socket2 =
	let lwt_socket = Lwt_zmq.Socket.of_socket socket in
	let lwt_socket2 = Lwt_zmq.Socket.of_socket socket2 in
	let loop () =
		Lwt_io.printl "Listening" >>=
		handle_recv lwt_socket >|=
		handle_reply >>=
		handoff lwt_socket2
	in
		while_lwt true
			do loop ()
			done

type ('a, 'b, 'c, 'd, 'e) t = {
	mongrel2_zmp_context : ZMQ.context;
	mongrel2_inbound : 'a ZMQ.Socket.t;
	mongrel2_outbound : 'b ZMQ.Socket.t;
	mongrel2_handler : 'c -> 'd -> 'e Lwt.t;
}

let fini z socket socket2 =
	ZMQ.Socket.close socket;
	ZMQ.Socket.close socket2;
	ZMQ.term z

let main_loop handler socket socket2 =
	Lwt_main.run (handler socket socket2)

let init inbound outbound mongrel_handler =
	let z = ZMQ.init () in
	let socket = ZMQ.Socket.create z ZMQ.Socket.pull in
	let socket2 = ZMQ.Socket.create z ZMQ.Socket.pub in
		{ mongrel2_zmp_context = z;
		  mongrel2_inbound = socket;
		  mongrel2_outbound = socket2;
		  mongrel2_handler = mongrel_handler;
		}

let run inbound outbound =
	let context = init inbound outbound mongrel_handler in
	let z = context.mongrel2_zmp_context in
	let socket = context.mongrel2_inbound in
	let socket2 = context.mongrel2_outbound in
		ZMQ.Socket.connect socket inbound;
		ZMQ.Socket.connect socket2 outbound;
		main_loop mongrel_handler socket socket2;
		fini z socket socket2
