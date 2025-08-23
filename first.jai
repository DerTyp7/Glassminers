#load "compiler.jai";
#load "print.jai";

DEVELOPER_OPTIONS := []string.[ "Developer" ];

Build_Mode :: enum {
    Debug;
    Release;
}

Build_Target :: enum {
    Executable;
    Library;
}

apply_flags :: (options: *Workspace_Options, mode: Build_Mode, target: Build_Target, release_subsystem: Subsystem) {
    options.type_information  = true;

    if #complete mode == {
      case .Debug;
        options.target_backend    = .X64;
        options.target_subsystem  = .Console;
        options.runtime_features  = .Bounds_Check | .Cast_Check | .Overflow_Check;
        options.debug_information = target == .Executable || options.target_backend == .C;
        options.user_options      = DEVELOPER_OPTIONS;
        
      case .Release;
        options.target_backend    = .C;
        options.target_subsystem  = release_subsystem;
        options.runtime_features  = .None;
        options.debug_information = false;
    }

    if #complete target == {
      case .Executable; options.target_output = .Executable;
      case .Library; options.target_output = .Static_Library;
    }
}

build_version_string_file :: () {
    system :: (line: cstring) -> s32 #foreign;

#if OS == .Windows {
    SYSTEM_CALL: cstring : "@echo off && for /f \"delims=\" %a in ('git rev-parse --short HEAD') do ECHO=VERSION_STRING :: \"%a\"; > shared\\VERSION_STRING.jai";
} #else #if OS == .Linux {
    SYSTEM_CALL: cstring : "echo VERSION_STRING :: \\\"$(git rev-parse --short HEAD)\\\"';' > shared/VERSION_STRING.jai";
}

    system(SYSTEM_CALL);
}

build_server :: (mode: Build_Mode, target: Build_Target) -> bool {
    options := compiler_default_workspace_options();
    options.workspace_name    = "Server";
    options.output_file_path  = "run_tree/server";
    options.source_files      = .[ "server/server.jai" ];
    apply_flags(*options, mode, target, .Console);
    return compiler_create_and_compile_workspace(*options);    
}

build_client :: (mode: Build_Mode) {
    if !build_server(mode, .Library) return;

    options := compiler_default_workspace_options();
    options.workspace_name    = "Client";
    options.output_file_path  = "run_tree/client";
    options.source_files      = .[ "client/client.jai" ];

    #if OS == .Windows {
        options.linker_options = .[ .{ .Library, "run_tree/server" }, .{ .String, "run_tree/data/icon/icon.res" } ];
    } #else {
        options.linker_options = .[ .{ .Library, "run_tree/server" } ];
    }
        
    apply_flags(*options, mode, .Executable, .Windows);
    compiler_create_and_compile_workspace(*options);
}

#run {
    build_version_string_file();
        
    options := compiler_get_active_workspace_options();
    if options.user_options.count {
        for i := 0; i < options.user_options.count; ++i {
            if options.user_options[i] == {
                case "debug"; build_client(.Debug);
                case "release"; build_client(.Release);
                case "server-debug"; build_server(.Debug, .Executable);
                case "server-release"; build_server(.Release, .Executable);
                case; print("Unknown build option, please specify one of: [ 'debug', 'release', 'server-debug', 'server-release' ].\n");
            }
        }
    } else {
        build_client(.Debug);
    }
}
