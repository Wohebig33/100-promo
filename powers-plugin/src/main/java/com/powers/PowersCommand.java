package com.powers;

import org.bukkit.Location;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabExecutor;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/** Handles /powers, /fly, /flyspeed, /speed, /noclip, /tracker and /waypoint. */
public final class PowersCommand implements TabExecutor {
    private static final List<String> WAYPOINT_SUBCOMMANDS = List.of("set", "go", "delete", "list");

    private final PowerManager powers;
    private final WaypointStore waypoints;
    private final Menus menus;

    public PowersCommand(PowerManager powers, WaypointStore waypoints, Menus menus) {
        this.powers = powers;
        this.waypoints = waypoints;
        this.menus = menus;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            Messages.error(sender, "Only players can use this.");
            return true;
        }

        switch (command.getName().toLowerCase(Locale.ROOT)) {
            case "powers" -> menus.openMain(player);
            case "fly" -> toggle(player, Power.FLY);
            case "noclip" -> toggle(player, Power.NOCLIP);
            case "tracker" -> toggle(player, Power.TRACKER);
            case "flyspeed" -> flySpeed(player, args);
            case "speed" -> speed(player, args);
            case "waypoint" -> waypoint(player, args);
            default -> {
                return false;
            }
        }
        return true;
    }

    private void toggle(Player player, Power power) {
        boolean turnOn = !powers.isOn(player, power);
        if (powers.setEnabled(player, power, turnOn)) {
            Messages.info(player, power.displayName() + (turnOn ? " on." : " off."));
        }
    }

    private void flySpeed(Player player, String[] args) {
        if (args.length != 1) {
            Messages.info(player, "Fly speed is " + powers.flyLevel(player) + ". Use /flyspeed <1-10> to change it.");
            return;
        }
        try {
            int level = powers.setFlyLevel(player, Integer.parseInt(args[0]));
            Messages.success(player, "Fly speed set to " + level + ".");
        } catch (NumberFormatException e) {
            Messages.error(player, "Fly speed must be a whole number from 1 to 10.");
        }
    }

    private void speed(Player player, String[] args) {
        if (args.length == 0) {
            toggle(player, Power.SPEED);
            return;
        }
        try {
            double multiplier = powers.setSpeedMultiplier(player, Double.parseDouble(args[0]));
            powers.setEnabled(player, Power.SPEED, true);
            Messages.success(player, "Speed boost on at x" + Messages.number(multiplier) + ".");
        } catch (NumberFormatException e) {
            Messages.error(player, "Speed must be a number from 1.5 to 5.");
        }
    }

    private void waypoint(Player player, String[] args) {
        if (args.length == 0) {
            menus.openWaypoints(player);
            return;
        }
        String sub = args[0].toLowerCase(Locale.ROOT);
        String name = args.length > 1 ? args[1] : null;

        switch (sub) {
            case "list" -> {
                List<WaypointStore.Waypoint> list = waypoints.list(player);
                if (list.isEmpty()) {
                    Messages.info(player, "You have no waypoints. Save one with /waypoint set <name>.");
                    return;
                }
                List<String> names = new ArrayList<>();
                for (WaypointStore.Waypoint wp : list) {
                    names.add(wp.name());
                }
                Messages.info(player, "Waypoints (" + list.size() + "): " + String.join(", ", names));
            }
            case "set" -> {
                if (name == null) {
                    name = waypoints.nextDefaultName(player);
                }
                switch (waypoints.add(player, name, player.getLocation())) {
                    case ADDED -> Messages.success(player, "Saved waypoint " + name + ".");
                    case REPLACED -> Messages.success(player, "Moved waypoint " + name + " to where you are.");
                    case INVALID_NAME -> Messages.error(player,
                            "Names can use letters, numbers, - and _ (up to 24 characters).");
                    case FULL -> Messages.error(player, "You can only have " + waypoints.max() + " waypoints.");
                }
            }
            case "go" -> {
                if (name == null) {
                    Messages.error(player, "Usage: /waypoint go <name>");
                    return;
                }
                Optional<WaypointStore.Waypoint> found = waypoints.find(player, name);
                if (found.isEmpty()) {
                    Messages.error(player, "No waypoint called " + name + ".");
                    return;
                }
                Location target = found.get().toLocation();
                if (target == null) {
                    Messages.error(player, "That waypoint's world isn't loaded.");
                    return;
                }
                String shownName = found.get().name();
                player.teleportAsync(target).thenAccept(ok -> {
                    if (ok) {
                        Messages.success(player, "Teleported to " + shownName + ".");
                    }
                });
            }
            case "delete", "remove" -> {
                if (name == null) {
                    Messages.error(player, "Usage: /waypoint delete <name>");
                } else if (waypoints.remove(player, name)) {
                    Messages.info(player, "Deleted waypoint " + name + ".");
                } else {
                    Messages.error(player, "No waypoint called " + name + ".");
                }
            }
            default -> Messages.error(player, "Usage: /waypoint [set|go|delete|list] [name]");
        }
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player) || args.length == 0) {
            return List.of();
        }
        String current = args[args.length - 1].toLowerCase(Locale.ROOT);
        List<String> options = switch (command.getName().toLowerCase(Locale.ROOT)) {
            case "flyspeed" -> args.length == 1
                    ? List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "10") : List.of();
            case "speed" -> args.length == 1
                    ? List.of("1.5", "2", "2.5", "3", "3.5", "4", "4.5", "5") : List.of();
            case "waypoint" -> {
                if (args.length == 1) {
                    yield WAYPOINT_SUBCOMMANDS;
                }
                if (args.length == 2 && List.of("go", "delete", "remove", "set").contains(args[0].toLowerCase(Locale.ROOT))) {
                    List<String> names = new ArrayList<>();
                    for (WaypointStore.Waypoint wp : waypoints.list(player)) {
                        names.add(wp.name());
                    }
                    yield names;
                }
                yield List.of();
            }
            default -> List.of();
        };

        List<String> matches = new ArrayList<>();
        for (String option : options) {
            if (option.toLowerCase(Locale.ROOT).startsWith(current)) {
                matches.add(option);
            }
        }
        return matches;
    }
}
