package com.powers;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextDecoration;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.inventory.ClickType;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.InventoryHolder;
import org.bukkit.inventory.ItemStack;

import java.util.ArrayList;
import java.util.List;

/**
 * The chest-style menus: the main powers menu and the waypoint list.
 * Items can't be taken out; clicks are handled here.
 */
public final class Menus implements Listener {
    // Main menu layout (27 slots): powers across the middle row, extras below
    private static final int SLOT_FLY = 10;
    private static final int SLOT_SPEED = 11;
    private static final int SLOT_NOCLIP = 12;
    private static final int SLOT_TRACKER = 13;
    private static final int SLOT_ESP = 14;
    private static final int SLOT_AIM = 15;
    private static final int SLOT_WAYPOINTS = 21;
    private static final int SLOT_ALL_OFF = 23;

    // Waypoint menu layout (54 slots): 0-44 waypoints, bottom row controls
    private static final int WAYPOINT_SLOTS = 45;
    private static final int SLOT_BACK = 45;
    private static final int SLOT_SAVE_HERE = 49;
    private static final int SLOT_CLOSE = 53;

    private final PowersPlugin plugin;
    private final PowerManager powers;
    private final WaypointStore waypoints;

    private enum Type { MAIN, WAYPOINTS }

    /** Marks our inventories so clicks in them are ours to handle. */
    private static final class MenuHolder implements InventoryHolder {
        private final Type type;
        private Inventory inventory;
        private List<WaypointStore.Waypoint> shown = List.of();

        private MenuHolder(Type type) {
            this.type = type;
        }

        @Override
        public Inventory getInventory() {
            return inventory;
        }
    }

    public Menus(PowersPlugin plugin, PowerManager powers, WaypointStore waypoints) {
        this.plugin = plugin;
        this.powers = powers;
        this.waypoints = waypoints;
    }

    // Opening -------------------------------------------------------------------

    public void openMain(Player player) {
        MenuHolder holder = new MenuHolder(Type.MAIN);
        holder.inventory = Bukkit.createInventory(holder, 27, Component.text("Powers"));
        renderMain(holder, player);
        player.openInventory(holder.inventory);
    }

    public void openWaypoints(Player player) {
        MenuHolder holder = new MenuHolder(Type.WAYPOINTS);
        holder.inventory = Bukkit.createInventory(holder, 54, Component.text("Waypoints"));
        renderWaypoints(holder, player);
        player.openInventory(holder.inventory);
    }

    // Rendering -----------------------------------------------------------------

    private void renderMain(MenuHolder holder, Player player) {
        Inventory inv = holder.inventory;
        fill(inv);

        int flyLevel = powers.flyLevel(player);
        inv.setItem(SLOT_FLY, powerItem(player, Power.FLY, Material.FEATHER, List.of(
                line("Fly speed: " + flyLevel + "/" + PowerManager.MAX_FLY_LEVEL, NamedTextColor.WHITE),
                Component.empty(),
                line("Left-click: turn on / off", NamedTextColor.GRAY),
                line("Right-click: faster", NamedTextColor.GRAY),
                line("Shift + right-click: slower", NamedTextColor.GRAY))));

        double speed = powers.speedMultiplier(player);
        inv.setItem(SLOT_SPEED, powerItem(player, Power.SPEED, Material.SUGAR, List.of(
                line("Speed: x" + Messages.number(speed), NamedTextColor.WHITE),
                Component.empty(),
                line("Left-click: turn on / off", NamedTextColor.GRAY),
                line("Right-click: faster", NamedTextColor.GRAY),
                line("Shift + right-click: slower", NamedTextColor.GRAY))));

        inv.setItem(SLOT_NOCLIP, powerItem(player, Power.NOCLIP, Material.ENDER_EYE, List.of(
                line("Fly through blocks (spectator mode).", NamedTextColor.WHITE),
                line("Your game mode comes back when you turn it off.", NamedTextColor.WHITE),
                Component.empty(),
                line("Click: turn on / off", NamedTextColor.GRAY))));

        inv.setItem(SLOT_TRACKER, powerItem(player, Power.TRACKER, Material.COMPASS, List.of(
                line("Shows the nearest players, their distance", NamedTextColor.WHITE),
                line("and direction above your hotbar.", NamedTextColor.WHITE),
                Component.empty(),
                line("Click: turn on / off", NamedTextColor.GRAY))));

        inv.setItem(SLOT_ESP, powerItem(player, Power.ESP, Material.SPYGLASS, List.of(
                line("See players' names, health and distance", NamedTextColor.WHITE),
                line("through walls. Only you see the labels.", NamedTextColor.WHITE),
                Component.empty(),
                line("Click: turn on / off", NamedTextColor.GRAY))));

        int aim = powers.aimStrength(player);
        inv.setItem(SLOT_AIM, powerItem(player, Power.AIM_ASSIST, Material.BOW, List.of(
                line("Strength: " + aim + "/" + PowerManager.MAX_AIM_STRENGTH, NamedTextColor.WHITE),
                line(aimTriggerText(), NamedTextColor.WHITE),
                Component.empty(),
                line("Left-click: turn on / off", NamedTextColor.GRAY),
                line("Right-click: stronger", NamedTextColor.GRAY),
                line("Shift + right-click: weaker", NamedTextColor.GRAY))));

        if (player.hasPermission("powers.waypoints")) {
            int count = waypoints.list(player).size();
            inv.setItem(SLOT_WAYPOINTS, item(Material.LODESTONE, title("Waypoints", NamedTextColor.AQUA), List.of(
                    line(count + " saved", NamedTextColor.WHITE),
                    Component.empty(),
                    line("Click: open", NamedTextColor.GRAY)), false));
        } else {
            inv.setItem(SLOT_WAYPOINTS, locked("Waypoints"));
        }

        inv.setItem(SLOT_ALL_OFF, item(Material.BARRIER, title("Turn everything off", NamedTextColor.RED),
                List.of(line("Click: turn off every power", NamedTextColor.GRAY)), false));
    }

    private String aimTriggerText() {
        String trigger = plugin.getConfig().getString("aim-assist.trigger", "ranged");
        return switch (trigger.toLowerCase(java.util.Locale.ROOT)) {
            case "always" -> "Pulls your aim toward the nearest target.";
            case "sneak" -> "Pulls your aim while you sneak.";
            default -> "Pulls your aim while drawing a bow or trident.";
        };
    }

    private ItemStack powerItem(Player player, Power power, Material material, List<Component> details) {
        if (!player.hasPermission(power.permission())) {
            return locked(power.displayName());
        }
        boolean on = powers.isOn(player, power);
        List<Component> lore = new ArrayList<>();
        lore.add(on ? line("● ON", NamedTextColor.GREEN) : line("○ OFF", NamedTextColor.DARK_GRAY));
        lore.addAll(details);
        return item(material, title(power.displayName(), on ? NamedTextColor.GREEN : NamedTextColor.WHITE), lore, on);
    }

    private void renderWaypoints(MenuHolder holder, Player player) {
        Inventory inv = holder.inventory;
        inv.clear();
        List<WaypointStore.Waypoint> list = waypoints.list(player);
        holder.shown = list.subList(0, Math.min(list.size(), WAYPOINT_SLOTS));

        for (int i = 0; i < holder.shown.size(); i++) {
            WaypointStore.Waypoint wp = holder.shown.get(i);
            World world = Bukkit.getWorld(wp.worldId());
            Material icon = world == null ? Material.MAP : switch (world.getEnvironment()) {
                case NETHER -> Material.NETHERRACK;
                case THE_END -> Material.END_STONE;
                default -> Material.GRASS_BLOCK;
            };
            List<Component> lore = new ArrayList<>();
            lore.add(line(world == null ? "World not loaded" : world.getName(),
                    world == null ? NamedTextColor.RED : NamedTextColor.WHITE));
            lore.add(line(String.format("x %.1f  y %.1f  z %.1f", wp.x(), wp.y(), wp.z()), NamedTextColor.WHITE));
            lore.add(Component.empty());
            lore.add(line("Left-click: go here", NamedTextColor.GRAY));
            lore.add(line("Shift + right-click: delete", NamedTextColor.GRAY));
            inv.setItem(i, item(icon, title(wp.name(), NamedTextColor.AQUA), lore, false));
        }

        for (int slot = WAYPOINT_SLOTS; slot < 54; slot++) {
            inv.setItem(slot, filler());
        }
        inv.setItem(SLOT_BACK, item(Material.ARROW, title("Back", NamedTextColor.WHITE), List.of(), false));
        inv.setItem(SLOT_SAVE_HERE, item(Material.LIME_DYE, title("Save waypoint here", NamedTextColor.GREEN), List.of(
                line(list.size() + "/" + waypoints.max() + " used", NamedTextColor.WHITE),
                line("To pick the name: /waypoint set <name>", NamedTextColor.GRAY)), false));
        inv.setItem(SLOT_CLOSE, item(Material.BARRIER, title("Close", NamedTextColor.RED), List.of(), false));
    }

    // Clicks --------------------------------------------------------------------

    @EventHandler
    public void onClick(InventoryClickEvent event) {
        if (!(event.getView().getTopInventory().getHolder() instanceof MenuHolder holder)) {
            return;
        }
        event.setCancelled(true); // nothing can be taken out or put in
        if (!(event.getWhoClicked() instanceof Player player)) {
            return;
        }
        if (event.getClickedInventory() != event.getView().getTopInventory()) {
            return;
        }
        switch (holder.type) {
            case MAIN -> clickMain(holder, player, event.getSlot(), event.getClick());
            case WAYPOINTS -> clickWaypoints(holder, player, event.getSlot(), event.getClick());
        }
    }

    @EventHandler
    public void onDrag(InventoryDragEvent event) {
        if (event.getView().getTopInventory().getHolder() instanceof MenuHolder) {
            event.setCancelled(true);
        }
    }

    private void clickMain(MenuHolder holder, Player player, int slot, ClickType click) {
        switch (slot) {
            case SLOT_FLY -> {
                if (click.isLeftClick()) {
                    powers.toggle(player, Power.FLY);
                } else if (click.isRightClick() && player.hasPermission(Power.FLY.permission())) {
                    int change = click.isShiftClick() ? -1 : 1;
                    powers.setFlyLevel(player, powers.flyLevel(player) + change);
                }
            }
            case SLOT_SPEED -> {
                if (click.isLeftClick()) {
                    powers.toggle(player, Power.SPEED);
                } else if (click.isRightClick() && player.hasPermission(Power.SPEED.permission())) {
                    double change = click.isShiftClick() ? -PowerManager.SPEED_STEP : PowerManager.SPEED_STEP;
                    powers.setSpeedMultiplier(player, powers.speedMultiplier(player) + change);
                }
            }
            case SLOT_NOCLIP -> powers.toggle(player, Power.NOCLIP);
            case SLOT_TRACKER -> powers.toggle(player, Power.TRACKER);
            case SLOT_ESP -> powers.toggle(player, Power.ESP);
            case SLOT_AIM -> {
                if (click.isLeftClick()) {
                    powers.toggle(player, Power.AIM_ASSIST);
                } else if (click.isRightClick() && player.hasPermission(Power.AIM_ASSIST.permission())) {
                    int change = click.isShiftClick() ? -1 : 1;
                    powers.setAimStrength(player, powers.aimStrength(player) + change);
                }
            }
            case SLOT_WAYPOINTS -> {
                if (player.hasPermission("powers.waypoints")) {
                    nextTick(() -> openWaypoints(player));
                }
                return;
            }
            case SLOT_ALL_OFF -> {
                for (Power power : Power.values()) {
                    powers.setEnabled(player, power, false);
                }
            }
            default -> {
                return;
            }
        }
        renderMain(holder, player);
    }

    private void clickWaypoints(MenuHolder holder, Player player, int slot, ClickType click) {
        if (slot < holder.shown.size()) {
            WaypointStore.Waypoint wp = holder.shown.get(slot);
            if (click == ClickType.SHIFT_RIGHT) {
                waypoints.remove(player, wp.name());
                Messages.info(player, "Deleted waypoint " + wp.name() + ".");
                renderWaypoints(holder, player);
            } else if (click.isLeftClick()) {
                Location target = wp.toLocation();
                if (target == null) {
                    Messages.error(player, "That waypoint's world isn't loaded.");
                    return;
                }
                nextTick(() -> {
                    player.closeInventory();
                    player.teleportAsync(target).thenAccept(ok -> {
                        if (ok) {
                            Messages.success(player, "Teleported to " + wp.name() + ".");
                        }
                    });
                });
            }
            return;
        }

        switch (slot) {
            case SLOT_BACK -> nextTick(() -> openMain(player));
            case SLOT_CLOSE -> nextTick(player::closeInventory);
            case SLOT_SAVE_HERE -> {
                String name = waypoints.nextDefaultName(player);
                WaypointStore.AddResult result = waypoints.add(player, name, player.getLocation());
                if (result == WaypointStore.AddResult.FULL) {
                    Messages.error(player, "You can only have " + waypoints.max() + " waypoints.");
                } else {
                    Messages.success(player, "Saved waypoint " + name + ".");
                }
                renderWaypoints(holder, player);
            }
            default -> {
            }
        }
    }

    // Item helpers --------------------------------------------------------------

    private void nextTick(Runnable task) {
        plugin.getServer().getScheduler().runTask(plugin, task);
    }

    private static Component title(String text, NamedTextColor color) {
        return Component.text(text, color).decoration(TextDecoration.ITALIC, false).decorate(TextDecoration.BOLD);
    }

    private static Component line(String text, NamedTextColor color) {
        return Component.text(text, color).decoration(TextDecoration.ITALIC, false);
    }

    private static ItemStack item(Material material, Component name, List<Component> lore, boolean glow) {
        ItemStack stack = new ItemStack(material);
        stack.editMeta(meta -> {
            meta.displayName(name);
            meta.lore(lore);
            if (glow) {
                meta.setEnchantmentGlintOverride(true);
            }
        });
        return stack;
    }

    private static ItemStack locked(String name) {
        return item(Material.GRAY_DYE, title(name, NamedTextColor.DARK_GRAY),
                List.of(line("Locked: you don't have this power.", NamedTextColor.RED)), false);
    }

    private static ItemStack filler() {
        return item(Material.GRAY_STAINED_GLASS_PANE, Component.text(" "), List.of(), false);
    }

    private static void fill(Inventory inv) {
        for (int slot = 0; slot < inv.getSize(); slot++) {
            inv.setItem(slot, filler());
        }
    }
}
