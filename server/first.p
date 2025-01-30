#load "compiler.p";

build_debug_exe :: () {
    options := compiler_default_workspace_options();
    options.workspace_name    = "Debug-Server";
    options.output_file_path  = "run_tree/server";
    options.object_file_path  = "run_tree/server";
    options.c_file_path       = "run_tree/server";
    options.source_files      = .[ "server/server.p" ];
    options.target_output     = .Executable;
    options.target_backend    = .X64;
    options.runtime_features  = .Bounds_Check | .Cast_Check | .Overflow_Check;
    options.debug_information = true;
    options.type_information  = true;
    compiler_create_and_compile_workspace(*options);
}

build_debug_lib :: () {
    options := compiler_default_workspace_options();
    options.workspace_name    = "Debug-Server";
    options.output_file_path  = "run_tree/server";
    options.object_file_path  = "run_tree/server";
    options.c_file_path       = "run_tree/server";
    options.source_files      = .[ "server/server.p" ];
    options.target_output     = .Static_Library;
    options.target_backend    = .X64;
    options.runtime_features  = .Bounds_Check | .Cast_Check | .Overflow_Check;
    options.debug_information = true;
    options.type_information  = true;
    compiler_create_and_compile_workspace(*options);
}

build_release_lib :: () {
    options := compiler_default_workspace_options();
    options.workspace_name    = "Release-Server";
    options.output_file_path  = "run_tree/server";
    options.object_file_path  = "run_tree/server";
    options.c_file_path       = "run_tree/server";
    options.source_files      = .[ "server/server.p" ];
    options.target_output     = .Static_Library;
    options.target_backend    = .C;
    options.runtime_features  = .None;
    options.debug_information = false;
    options.type_information  = true;
    compiler_create_and_compile_workspace(*options);    
}

//#run build_debug_exe();
#run build_debug_lib();
//#run build_release_lib();
