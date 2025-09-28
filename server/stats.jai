reset_statistics :: (stats: []Statistic) {
    for i := 0; i < stats.count; ++i {
        stats[i] = .{};
    }
}

reset_all_statistics :: (server: *Server) {
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        for j := 0; j < client.local_player_count; ++j {
            reset_statistics(client.local_players[i].stats);
        }
    }

    reset_statistics(server.global_stats);
}

increase_player_statistic :: (server: *Server, guy_pid: Pid, kind: Player_Stat_Kind) {
    player := find_local_player_by_guy_pid(server, guy_pid);
    assert(player != null, "Tried to increase a player stat for a non-existent player.");
    
    stat := *player.stats[kind];
    increase(stat);

    should_send: bool = ---;

    if #complete kind == {
      case .Completed_Moves; should_send = stat.counter % 2 == 0; // @Incomplete
    }

    if should_send {
        send_player_stat_message(server, kind, player);
    }
}

increase_global_statistic :: (server: *Server, kind: Global_Stat_Kind) {
    stat := *server.global_stats[kind];
    increase(stat);

    should_send: bool = ---;

    if #complete kind == {
      case .Monsters_Killed; should_send = stat.counter % 2 == 0; // @Incomplete
    }

    if should_send {    
        send_global_stat_message(server, kind);
    }
}



#file_scope

increase :: (stat: *Statistic) {
    ++stat.counter;
}

send_player_stat_message :: (server: *Server, stat: Player_Stat_Kind, player: *Local_Player) {
    msg := make_message(Player_Stat_Message);
    msg.player_stat.guy_pid = player.guy_pid;
    msg.player_stat.kind = stat;
    msg.player_stat.stat = player.stats[stat];
    array_add(*server.outgoing_messages, msg);
}

send_global_stat_message :: (server: *Server, stat: Global_Stat_Kind) {
    msg := make_message(Global_Stat_Message);
    msg.global_stat.kind = stat;
    msg.global_stat.stat = server.global_stats[stat];
    array_add(*server.outgoing_messages, msg);
}
