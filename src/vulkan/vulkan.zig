const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const zglfw = @import("zglfw");

const DebugUtils = @import("debug_utils.zig");

const base_commands: vk.BaseCommandFlags = .{
    .createInstance = true,
    .getInstanceProcAddr = true,
    .enumerateInstanceLayerProperties = true,
};

const instance_commands: vk.InstanceCommandFlags = .{
    .createDevice = true,
    .destroyInstance = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
};

const device_commands: vk.DeviceCommandFlags = .{
    .destroyDevice = true,
};

const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = base_commands,
        .instance_commands = instance_commands,
        .device_commands = device_commands,
    },
    vk.features.version_1_2,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
    vk.extensions.khr_portability_enumeration,
};

pub const BaseDispatcher = vk.BaseWrapper(apis);
pub const InstanceDispatcher = vk.InstanceWrapper(apis);
pub const DeviceDispatcher = vk.DeviceWrapper(apis);

pub const InstanceProxy = vk.InstanceProxy(apis);
pub const DeviceProxy = vk.DeviceProxy(apis);

const validation_layers = [_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub const VulkanContext = struct {
    allocator: std.mem.Allocator,
    base_dispatcher: BaseDispatcher,
    debug_messenger: vk.DebugUtilsMessengerEXT,

    instance: InstanceProxy,

    pub fn initDefault(
        allocator: std.mem.Allocator,
        window_extensions: std.ArrayList([*:0]const u8),
    ) !VulkanContext {
        const base_dispatcher = try BaseDispatcher.load(glfwGetInstanceProcAddress);

        const available_layers = try base_dispatcher.enumerateInstanceLayerPropertiesAlloc(allocator);
        defer allocator.free(available_layers);

        var layer_found = false;
        for (validation_layers) |v_layer| {
            for (available_layers) |a_layer| {
                if (std.mem.startsWith(u8, a_layer.layer_name[0..], v_layer[0..])) {
                    layer_found = true;
                    break;
                }
            }
        }

        var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 8);
        defer extensions.deinit();

        try extensions.appendSlice(window_extensions.items[0..]);
        try extensions.append(vk.extensions.khr_portability_enumeration.name);

        if (builtin.mode == .Debug) {
            try extensions.append(vk.extensions.ext_debug_utils.name);
        }

        const app_info: vk.ApplicationInfo = .{
            .p_application_name = "test",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "test_engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        };

        var instance_info: vk.InstanceCreateInfo = .{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(extensions.items),
            .flags = if (comptime builtin.target.os.tag == .macos) vk.InstanceCreateFlags{ .enumerate_portability_bit_khr = true } else .{},
        };

        // Create the Vulkan instance
        var debug_ci: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
        if (builtin.mode == .Debug and layer_found) {
            std.log.info("Setting validation layers and instance debug logging", .{});
            debug_ci = DebugUtils.CreateDefaultDebugUtilsCreateInfo();

            instance_info.enabled_layer_count = @intCast(validation_layers.len);
            instance_info.pp_enabled_layer_names = @ptrCast(&validation_layers);
            instance_info.p_next = @as(*vk.DebugUtilsMessengerCreateInfoEXT, &debug_ci);
        }

        const instance = try base_dispatcher.createInstance(&instance_info, null);
        const vki = try allocator.create(InstanceDispatcher);
        errdefer allocator.destroy(vki);

        vki.* = try InstanceDispatcher.load(instance, base_dispatcher.dispatch.vkGetInstanceProcAddr);
        const vk_instance = InstanceProxy.init(instance, vki);
        errdefer instance.destroyInstance(null);

        // Add debug logging.
        var debug_messenger: vk.DebugUtilsMessengerEXT = undefined;
        if (builtin.mode == .Debug) {
            debug_ci = DebugUtils.CreateDefaultDebugUtilsCreateInfo();

            DebugUtils.createDebugUtilsMessenger(
                base_dispatcher,
                vk_instance.handle,
                &debug_ci,
                &debug_messenger,
            );
        }

        return VulkanContext{
            .allocator = allocator,
            .debug_messenger = debug_messenger,
            .base_dispatcher = base_dispatcher,
            .instance = vk_instance,
        };
    }

    pub fn deinit(self: VulkanContext) void {
        if (builtin.mode == .Debug) {
            DebugUtils.destroyDebugUtilsMessenger(
                self.base_dispatcher,
                self.instance.handle,
                self.debug_messenger,
            );
        }

        self.instance.destroyInstance(null);
        self.allocator.destroy(self.instance.wrapper);
    }
};

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
