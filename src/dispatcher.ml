
(*
  XBreed, a Mongrel2 handler for OCaml

  Copyright (C) 2013  Martin Keegan

  This programme is free software; you may redistribute and/or modify
  it under the terms of the Apache License v2.0
*)

(* this code isn't even supposed to be alpha quality - it's just a hack ATM *)

open Lwt
open Mongrel2

let dispatch handlers handle_404 request =
	let status_from_error = function
		| Unix.Unix_error (Unix.ENOENT, _, _)
		| Unix.Unix_error (Unix.EISDIR, _, _) -> Code.Not_Found
		| _ -> Code.Internal_server_error
	in
		
	let guard f =
		try_lwt f ()
		with exn ->
			let error = Printexc.to_string exn in
			let status = status_from_error exn in
				Lwt_io.printlf "Error: `%s'" error >>=
					fun () ->
				Lwt_io.printl (Printexc.get_backtrace ()) >>=
					fun () -> Generator.return_generic_error status

	in

	let rec handle matches = function
		| [] -> handle_404 request [||]
		| (url_regexp, handler) :: tl ->
			try_lwt let args = matches url_regexp in
						guard (fun () -> handler request args)
            with Not_found ->
				handle matches tl
	in
		try_lwt let uri = uri_of_request request in
				let matches pat = Pcre.extract ~pat uri	in
					Lwt_io.printlf "URI: %s" uri >>= 
						fun () -> handle matches handlers
		with exn ->
			let error = Printexc.to_string exn in
			let status = status_from_error exn in
				Lwt_io.printlf "Error determining/matching URI: `%s'" error >>=
					fun () ->
				Lwt_io.printl (Printexc.get_backtrace ()) >>=
					fun () -> Generator.return_generic_error status
	
let make handlers not_found =
	dispatch handlers not_found

