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
    .getDeviceProcAddr = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
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

pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);

const validation_layers = [_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const required_device_extensions = [_][*:0]const u8{
    // vk.extensions.khr_portability_enumeration.name,
    vk.extensions.khr_portability_subset.name,
    vk.extensions.khr_swapchain.name,
};

pub const VulkanInitError = error{
    NoDevicesFound,
    NoSuitableDeviceFound,
};

const DeviceCandidate = struct {
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    queues: QueueFamilyIndices,
    score: u32,
};

const QueueFamilyIndices = struct {
    graphics_queue: u32,
};

pub const VulkanContext = struct {
    allocator: std.mem.Allocator,
    base_dispatcher: BaseDispatcher,
    debug_messenger: vk.DebugUtilsMessengerEXT,

    instance: Instance,
    physical_device: DeviceCandidate,
    device: Device,
    gfx_queue: vk.Queue,

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
        const vk_instance = Instance.init(instance, vki);
        errdefer vk_instance.destroyInstance(null);

        // Add debug logging.
        var debug_messenger: vk.DebugUtilsMessengerEXT = undefined;
        if (validation_layers.len > 0) {
            debug_ci = DebugUtils.CreateDefaultDebugUtilsCreateInfo();

            DebugUtils.createDebugUtilsMessenger(
                base_dispatcher,
                vk_instance.handle,
                &debug_ci,
                &debug_messenger,
            );
        }

        // Pick Physical device and create logical device.
        const p_device: DeviceCandidate = try pickPhysicalDevice(allocator, vk_instance);
        const dev = try createLogicalDevice(vk_instance, p_device);

        const vkd = try allocator.create(DeviceDispatcher);
        errdefer allocator.destroy(vkd);
        vkd.* = try DeviceDispatcher.load(dev, vk_instance.wrapper.dispatch.vkGetDeviceProcAddr);
        const device = Device.init(dev, vkd);
        errdefer dev.destroyDevice(null);

        // Create graphics queue.
        const gfx_queue: vk.Queue = device.getDeviceQueue(p_device.queues.graphics_queue);

        // Return
        return VulkanContext{
            .allocator = allocator,
            .debug_messenger = debug_messenger,
            .base_dispatcher = base_dispatcher,
            .instance = vk_instance,
            .physical_device = p_device,
            .device = device,
        };
    }

    pub fn deinit(self: VulkanContext) void {
        if (validation_layers.len > 0) {
            DebugUtils.destroyDebugUtilsMessenger(
                self.base_dispatcher,
                self.instance.handle,
                self.debug_messenger,
            );
        }

        self.device.destroyDevice(null);
        self.instance.destroyInstance(null);
        self.allocator.destroy(self.device.wrapper);
        self.allocator.destroy(self.instance.wrapper);
    }

    fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: Instance) !DeviceCandidate {
        const p_devs = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(p_devs);

        if (p_devs.len == 0) {
            std.log.err("Failed to find physical devices with Vulkan support", .{});
            return VulkanInitError.NoDevicesFound;
        }

        var p_device: ?DeviceCandidate = null;

        for (p_devs) |dev| {
            if (try isDeviceSuitable(allocator, instance, dev)) |c| {
                p_device = c;
                break;
            }
        }

        if (p_device == null) {
            std.log.err("Failed to find suitable physical device", .{});
            return VulkanInitError.NoSuitableDeviceFound;
        }

        return p_device.?;
    }

    fn isDeviceSuitable(
        allocator: std.mem.Allocator,
        instance: Instance,
        p_device: vk.PhysicalDevice,
    ) !?DeviceCandidate {
        const dev_props: vk.PhysicalDeviceProperties = instance.getPhysicalDeviceProperties(p_device);
        const dev_feats: vk.PhysicalDeviceFeatures = instance.getPhysicalDeviceFeatures(p_device);

        // NOTE: one can implement their own heuristics here..
        if (try findQueueFamilies(allocator, instance, p_device)) |queues| {
            return DeviceCandidate{
                .physical_device = p_device,
                .properties = dev_props,
                .features = dev_feats,
                .score = 100,
                .queues = queues,
            };
        }

        return null;
    }

    fn findQueueFamilies(
        allocator: std.mem.Allocator,
        instance: Instance,
        device: vk.PhysicalDevice,
    ) !?QueueFamilyIndices {
        const queue_family_props = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);
        defer allocator.free(queue_family_props);

        var graphics_family: ?u32 = null;

        for (queue_family_props, 0..) |props, i| {
            const family: u32 = @intCast(i);

            if (graphics_family == null and props.queue_flags.graphics_bit) {
                graphics_family = family;
            }
        }

        if (graphics_family != null) {
            return QueueFamilyIndices{
                .graphics_queue = graphics_family.?,
            };
        }

        return null;
    }

    fn createLogicalDevice(
        instance: Instance,
        candidate: DeviceCandidate,
    ) !vk.Device {
        const gfw_prio = [_]f32{1.0};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = candidate.queues.graphics_queue,
                .queue_count = 1,
                .p_queue_priorities = &gfw_prio,
            },
        };

        var dci: vk.DeviceCreateInfo = undefined;
        dci.s_type = vk.StructureType.device_create_info;
        dci.p_queue_create_infos = @ptrCast(&qci);
        dci.queue_create_info_count = 1;

        const device = try instance.createDevice(
            candidate.physical_device,
            &vk.DeviceCreateInfo{
                .s_type = vk.StructureType.device_create_info,
                .p_queue_create_infos = &qci,
                .queue_create_info_count = 1,
                .enabled_layer_count = validation_layers.len,
                .pp_enabled_layer_names = @ptrCast(&validation_layers),
                .enabled_extension_count = required_device_extensions.len,
                .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
            },
            null,
        );
        return device;
    }
};

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
