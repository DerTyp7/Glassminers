#load "compiler.jai";

Build_Mode :: enum {
    Debug;
    Release;
}

Build_Target :: enum {
    Executable;
    Library;
}

apply_flags :: (options: *Workspace_Options, mode: Build_Mode, target: Build_Target) {
    if #complete mode == {
      case .Debug;
        options.target_backend    = .X64;
        options.runtime_features  = .Bounds_Check | .Cast_Check | .Overflow_Check;
        options.debug_information = target == .Executable;

      case .Release;
        options.target_backend    = .C;
        options.runtime_features  = .None;
        options.debug_information = false;
    }

    if #complete target == {
      case .Executable; options.target_output = .Executable;
      case .Library; options.target_output = .Static_Library;
    }
}

build_server :: (mode: Build_Mode, target: Build_Target) {
    options := compiler_default_workspace_options();
    options.workspace_name    = "Server";
    options.output_file_path  = "run_tree/server";
    options.source_files      = .[ "server/server.jai" ];
    options.type_information  = true;
    apply_flags(*options, mode, target);
    compiler_create_and_compile_workspace(*options);    
}

build_client :: (mode: Build_Mode) {
    build_server(mode, .Library);

    options := compiler_default_workspace_options();
    options.workspace_name    = "Client";
    options.output_file_path  = "run_tree/client";
    options.source_files      = .[ "client/client.jai" ];
    options.linker_options    = .[ .{ .Library, "run_tree/server" } ];
    options.type_information  = true;
    apply_flags(*options, mode, .Executable);
    compiler_create_and_compile_workspace(*options);
}

#run {
    options := compiler_get_active_workspace_options();
    if options.user_options.count {
        for i := 0; i < options.user_options.count; ++i {
            if options.user_options[i] == {
                case "debug"; build_client(.Debug);
                case "release"; build_client(.Release);
                case "server-debug"; build_server(.Debug, .Executable);
                case "server-release"; build_server(.Release, .Executable);
            }
        }
    } else {
        build_client(.Debug);
    }
}
