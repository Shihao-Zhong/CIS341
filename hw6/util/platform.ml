(* -------------------------------------------------------------------------- *)
(** Assembling and linking for X86.  Depends on the underlying OS platform    *)


open Printf
open Unix

exception PlatformError of string * string


(* -------------------------------------------------------------------------- *)
(* Platform specific configuration: Unix/Linux vs. Mac OS X                   *)

let os = Sys.os_type   (* One of "Unix" "Win32" or "Cygwin" *)

(* Default to Mac OS X configuration *)
let opt_level = ref "-O1"
let linux = ref false
let target_triple = ref "x86_64-apple-macosx10.10.0"
let platform_flags = ref "-fno-asynchronous-unwind-tables -mstackrealign"

let mangle name = if !linux then name else ("_" ^ name)

let linux_target_triple = "x86_64-unknown-linux"
let common_flags = "-Wno-override-module"
let clang_ll_mode = "-S"
let as_mode = "-c" 

let clang args =
  Printf.sprintf "clang %s -o " (String.concat " " args)

let clang_cmd () = clang [clang_ll_mode; !opt_level; common_flags; !platform_flags]
let as_cmd ()    = clang [as_mode; !opt_level; common_flags; !platform_flags]
let link_cmd ()  = clang [common_flags; !opt_level; !platform_flags]

let pp_cmd = ref "cpp -E " 
let rm_cmd = ref "rm -rf " 

let verbose = ref false
let verb msg = (if !verbose then (print_string msg; flush Pervasives.stdout))

      
(* paths -------------------------------------------------------------------- *)

let path_sep = "/"
let dot_path = "./"
let output_path = ref "output"
let libs = ref [] 
let lib_paths = ref []
let lib_search_paths = ref []
let include_paths = ref []
let executable_name = ref "a.out"

(* Set the link commands properly, ensure output directory exists *)
let configure () =
  if os <> "Unix" then failwith "Windows not supported";
  if !linux 
  then (verb "platform = linux\n";
        target_triple := linux_target_triple;
        platform_flags := "")
  else verb "platform = OS X\n";
  try ignore (stat !output_path)
  with Unix_error (ENOENT,_,_) ->
    (verb @@ Printf.sprintf "creating output directory: %s\n" !output_path);
    mkdir !output_path 0o755

(* filename munging --------------------------------------------------------- *)
let path_to_basename_ext (path:string) : string * string =
  (* The path is of the form ... "foo/bar/baz/<file>.ext" *)
  let paths = Str.split (Str.regexp_string path_sep) path in
  let _ = if (List.length paths) = 0 then failwith @@ sprintf "bad path: %s" path in
  let filename = List.hd (List.rev paths) in
  match Str.split (Str.regexp_string ".") filename with
  | [root] -> root, ""
  | [root; ext] -> root, ext
  | _ -> failwith @@ sprintf "bad filename: %s" filename

(* compilation and shell commands-------------------------------------------- *)

(* Platform independent shell command *)  
let sh (cmd:string) (ret:string -> int -> 'a) : 'a =
  verb (sprintf "* %s\n" cmd);
  match (system cmd) with
  | WEXITED   i -> ret cmd i
  | WSIGNALED i -> raise (PlatformError (cmd, sprintf "Signaled with %d." i))
  | WSTOPPED  i -> raise (PlatformError (cmd, sprintf "Stopped with %d." i))

(* Generate a name that does not already exist.
   basedir includes the path separator
*)
let gen_name (basedir:string) (basen:string) (baseext:string) : string =  
  let rec nocollide ofs =
    let nfn = sprintf "%s/%s%s%s" basedir basen
        (if ofs = 0 then "" else "_"^(string_of_int ofs)) baseext
    in
      try ignore (stat nfn); nocollide (ofs + 1)
      with Unix_error (ENOENT,_,_) -> nfn
  in nocollide 0


let raise_error cmd i =
  if i <> 0 then raise (PlatformError (cmd, sprintf "Exited with status %d." i))

let ignore_error _ _ = ()

let clang_compile (dot_ll:string) (dot_s:string) : unit =
  sh (sprintf "%s%s %s" (clang_cmd ()) dot_s dot_ll) raise_error

let assemble (dot_s:string) (dot_o:string) : unit =
  sh (sprintf "%s%s %s" (as_cmd ()) dot_o dot_s) raise_error

let preprocess (dot_oat:string) (dot_i:string) : unit =
  sh (sprintf "%s%s %s %s" !pp_cmd 
	(List.fold_left (fun s -> fun i -> s ^ " -I" ^ i) "" !include_paths)
        dot_oat dot_i) raise_error

let link (mods:string list) (out_fn:string) : unit =
  sh (sprintf "%s%s %s %s %s %s" (link_cmd ()) out_fn 
	(String.concat " " (mods @ !lib_paths))
	(List.fold_left (fun s -> fun i -> s ^ " -L" ^ i) "" !lib_search_paths)
	(List.fold_left (fun s -> fun i -> s ^ " -I" ^ i) "" !include_paths)
        (List.fold_left (fun s -> fun l -> s ^ " -l" ^ l) "" !libs))
    raise_error



