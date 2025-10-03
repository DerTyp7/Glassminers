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
      case .Resurrections;       should_send = stat.counter % 5 == 0;
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

//
// :StatScoring
// In short, we want to find the "most interesting" stat to display, or return .Count if no stat
// is considered interesting enough.
// We select the most interesting stat by scoring each statistic through some defined function.
// The different stats are balanced by defining different linear curves for them. I basically
// solved for X (Stat Counter) when F(X) = 100 Score, to have a baseline of what the counter
// of each stat would have to be for all of them to be equally as "interesting".
//

find_game_over_player_stat :: (server: *Server) -> Player_Stat_Kind, Pid, Statistic {
    best_stat_kind: Player_Stat_Kind = .Count;
    best_guy_pid: Pid = ---;
    best_stat: Statistic = ---;
    best_score := calculate_score_threshold(server);

    for ci := 0; ci < server.clients.count; ++ci {
        client := array_get_pointer(*server.clients, ci);
        for li := 0; li < client.local_player_count; ++li {
            local_player := *client.local_players[li];

            for stat := 0; stat < Player_Stat_Kind.Count; ++stat {
                score := calculate_player_score(server, local_player, stat);
                if score > best_score {
                    best_stat      = local_player.stats[stat];
                    best_score     = score;
                    best_guy_pid   = local_player.guy_pid;
                    best_stat_kind = stat;
                }
            }
        }
    }

    return best_stat_kind, best_guy_pid, best_stat;
}

find_game_over_global_stat :: (server: *Server) -> Global_Stat_Kind, Statistic {
    best_stat_kind: Global_Stat_Kind = .Count;
    best_stat: Statistic = ---;
    best_score := calculate_score_threshold(server);

    for stat := 0; stat < Global_Stat_Kind.Count; ++stat {
        score := calculate_global_score(server, stat);
        if score > best_score {
            best_stat      = server.global_stats[stat];
            best_score     = score;
            best_stat_kind = stat;
        }
    }

    return best_stat_kind, best_stat;
}



#file_scope

SCORE_RANDOMNESS: s64 : 15;

increase :: (stat: *Statistic) {
    ++stat.counter;
}

calculate_score_threshold :: (server: *Server) -> s64 {
    return max((server.current_section_index + 1) * 10, 40);
}

calculate_global_score :: (server: *Server, kind: Global_Stat_Kind) -> s64 {
    base_score: s64 = ---;
    counter := server.global_stats[kind].counter;

    if #complete kind == {
      case .Monsters_Killed;  base_score = counter * 2;
      case .Sections_Reached; base_score = counter * 7;
    }

    return base_score + random_u64_in(*server.entity_random, 0, SCORE_RANDOMNESS);
}

calculate_player_score :: (server: *Server, player: *Local_Player, kind: Player_Stat_Kind) -> s64 {
    base_score: s64 = ---;
    counter := player.stats[kind].counter;

    if #complete kind == {
      case .Moves;               base_score = counter / 50;
      case .Deaths;              base_score = counter * 15;
      case .Resurrections;       base_score = counter * 10;
      case .Resources_Mined;     base_score = counter * 1;
      case .Mirrors_Constructed; base_score = counter * 2;
      case .Coins_Spent_Total;   base_score = counter * 2;
      case .Coins_Spent_Healing; base_score = counter * 3;
      case .Damage_Taken;        base_score = counter / 2;
    }

    return base_score + random_u64_in(*server.entity_random, 0, SCORE_RANDOMNESS);
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
