package com.powers;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextDecoration;
import org.bukkit.command.CommandSender;

/** Chat message helpers so every message looks the same. */
public final class Messages {
    private static final Component PREFIX = Component.text("Powers ", NamedTextColor.AQUA)
            .decorate(TextDecoration.BOLD)
            .append(Component.text("» ", NamedTextColor.DARK_GRAY).decoration(TextDecoration.BOLD, false));

    private Messages() {
    }

    public static void info(CommandSender to, String text) {
        to.sendMessage(PREFIX.append(Component.text(text, NamedTextColor.GRAY).decoration(TextDecoration.BOLD, false)));
    }

    public static void success(CommandSender to, String text) {
        to.sendMessage(PREFIX.append(Component.text(text, NamedTextColor.GREEN).decoration(TextDecoration.BOLD, false)));
    }

    public static void error(CommandSender to, String text) {
        to.sendMessage(PREFIX.append(Component.text(text, NamedTextColor.RED).decoration(TextDecoration.BOLD, false)));
    }

    /** Formats a multiplier like 2.0 as "2" and 2.5 as "2.5". */
    public static String number(double value) {
        return value == Math.rint(value) ? Long.toString((long) value) : Double.toString(value);
    }
}
