
(*
  XBreed, a Mongrel2 handler for OCaml

  Copyright (C) 2013  Martin Keegan

  This programme is free software; you may redistribute and/or modify
  it under the terms of the Apache License v2.0
*)

(* this code isn't even supposed to be alpha quality - it's just a hack ATM *)

	val make : 
		(string * Generator.handler) list -> 
		Generator.handler ->
        Mongrel2.mongrel2_request -> 
		Mongrel2.mongrel2_response Lwt.t

