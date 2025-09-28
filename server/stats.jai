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

increment_player_statistic :: (server: *Server, guy_pid: Pid, kind: Player_Stat_Kind) {
    player := find_local_player_by_guy_pid(server, guy_pid);
    assert(player != null, "Tried to increase a player stat for a non-existent player.");
    
    stat := *player.stats[kind];
    increase(stat);

    should_send: bool = ---;

    if #complete kind == {
      case .Moves;               should_send = stat.counter % 500 == 0;
      case .Deaths;              should_send = stat.counter % 5 == 0;
      case .Guys_Resurrected;    should_send = stat.counter % 5 == 0;
      case .Resources_Mined;     should_send = stat.counter % 20 == 0;
      case .Mirrors_Constructed; should_send = stat.counter % 15 == 0;
      case .Coins_Spent_Total;   should_send = stat.counter % 15 == 0;
      case .Coins_Spent_Healing; should_send = stat.counter % 10 == 0;
      case .Damage_Taken;        should_send = stat.counter % (cast(s64) HEALTH_PER_HEART * 20) == 0;
    }

    if should_send {
        send_player_stat_message(server, kind, player);
    }
}

increase_player_statistic :: (server: *Server, guy_pid: Pid, kind: Player_Stat_Kind, count: s64) {
    // This is really dumb, but our logic of determining whether to broadcast a statistic out to the
    // clients usually depends on a modulo (meaning we need to match the exact value once to send it out).
    // Therefore, this is the easiest solution. Increasing by more than one also rarely happens anyway...
    for i := 0; i < count; ++i {
        increment_player_statistic(server, guy_pid, kind);
    }
}

increment_global_statistic :: (server: *Server, kind: Global_Stat_Kind) {
    stat := *server.global_stats[kind];
    increase(stat);

    should_send: bool = ---;

    if #complete kind == {
      case .Monsters_Killed;  should_send = stat.counter % 30 == 0;
      case .Sections_Reached; should_send = true;
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
