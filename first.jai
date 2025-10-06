#load "compiler.jai";
#load "print.jai";

DEVELOPER_OPTIONS := []string.[ "Developer" ];

Build_Mode :: enum {
    Debug;
    Release_With_Debug_Info;
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
        options.target_backend     = .X64;
        options.target_subsystem   = .Console;
        options.runtime_features   = .Bounds_Check | .Cast_Check | .Overflow_Check;
        options.optimization_level = .Unoptimized;
        options.debug_information  = target == .Executable || options.target_backend == .C;
        options.user_options       = DEVELOPER_OPTIONS;

      case .Release_With_Debug_Info;
        options.target_backend     = .C;
        options.target_subsystem   = release_subsystem;
        options.runtime_features   = .Bounds_Check | .Cast_Check | .Overflow_Check;
        options.optimization_level = .Optimized;
        options.debug_information  = target == .Executable || options.target_backend == .C;

      case .Release;
        options.target_backend     = .C;
        options.target_subsystem   = release_subsystem;
        options.runtime_features   = .None;
        options.optimization_level = .Optimized;
        options.debug_information  = false;
    }

    if #complete target == {
      case .Executable; options.target_output = .Executable;
      case .Library; options.target_output = .Static_Library;
    }
}

build_version_string_file :: () {
    system :: (line: cstring) -> s32 #foreign;

    build_directory := compiler_get_current_source_directory();

#if OS == .Windows {
    SYSTEM_CALL_TEMPLATE :: "@echo off && for /f \"delims=\" \\%a in ('git -C % rev-parse --short HEAD') do ECHO=VERSION_STRING :: \"\\%a\"; > %\\shared\\VERSION_STRING.jai";
} #else #if OS == .Linux {
    SYSTEM_CALL_TEMPLATE :: "echo VERSION_STRING :: \\\"$(git -C % rev-parse --short HEAD)\\\"';' > %/shared/VERSION_STRING.jai";
}

    system_call_string := print_into_allocator(Default_Allocator, SYSTEM_CALL_TEMPLATE, build_directory, build_directory);
    system(to_cstring(Default_Allocator, system_call_string));
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
        build_directory := compiler_get_current_source_directory();
        icon_resource := print_into_allocator(Default_Allocator, "%/run_tree/data/icon/icon.res", build_directory); // The compiler automatically adjusts these paths for source and library options, but not for these custom strings...

        options.linker_options = .[ .{ .Library, "run_tree/server" }, .{ .String, icon_resource } ];
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
              case "release-with-debug"; build_client(.Release_With_Debug_Info);
              case "server-debug"; build_server(.Debug, .Executable);
              case "server-release"; build_server(.Release, .Executable);
              case "server-with-debug"; build_server(.Release_With_Debug_Info, .Executable);
              case; print("Unknown build option, please specify one of: [ 'debug', 'release', 'release-with-debug', 'server-debug', 'server-release', 'server-with-debug' ].\n");
            }
        }
    } else {
        build_client(.Debug);
    }
}
