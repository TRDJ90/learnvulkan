const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");

const BaseDispatch = vulkan.BaseDispatch;
const InstanceDispatch = vulkan.InstanceDispatch;
const DeviceDispatch = vulkan.DeviceDispatch;

const Instance = vulkan.Instance;
const Device = vulkan.Device;

const window_title = "Learn webgpu";

fn initVulkan(allocator: std.mem.Allocator) !void {
    const base_dispatch = try BaseDispatch.load(glfwGetInstanceProcAddress);

    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 8);
    defer extensions.deinit();

    const glfw_extensions = try zglfw.getRequiredInstanceExtensions();
    for (glfw_extensions) |ext| {
        try extensions.append(ext);
    }
    try extensions.append(vk.extensions.khr_portability_enumeration.name);

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = "test",
        .application_version = vk.makeApiVersion(0, 0, 0, 0),
        .p_engine_name = "test_engine",
        .engine_version = vk.makeApiVersion(0, 0, 0, 0),
        .api_version = vk.API_VERSION_1_2,
    };

    // check validation layer
    var validation_layer_names = try std.ArrayList([]const u8).initCapacity(allocator, 2);
    defer validation_layer_names.deinit();
    try validation_layer_names.append("VK_LAYER_KHRONOS_validation");

    const available_layers = try base_dispatch.enumerateInstanceLayerPropertiesAlloc(allocator);
    defer allocator.free(available_layers);

    var layer_found = false;
    for (validation_layer_names.items) |v_layer| {
        for (available_layers) |a_layer| {
            if (std.mem.startsWith(u8, a_layer.layer_name[0..], v_layer[0..])) {
                layer_found = true;
                break;
            }
        }
    }
    std.log.info("Layer: {}", .{layer_found});

    var instance_ci: vk.InstanceCreateInfo = .{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(extensions.items),
    };

    if (comptime builtin.target.os.tag == .macos) {
        instance_ci.flags = vk.InstanceCreateFlags{
            .enumerate_portability_bit_khr = true,
        };
    }

    if (builtin.mode == .Debug and layer_found) {
        std.log.info("Setting validation layers", .{});
        instance_ci.enabled_layer_count = @intCast(validation_layer_names.items.len);
        instance_ci.pp_enabled_layer_names = @ptrCast(validation_layer_names.items);
    }

    // Create vulkan instance
    const instance = try base_dispatch.createInstance(&instance_ci, null);
    const vki = try allocator.create(InstanceDispatch);
    errdefer allocator.destroy(vki);

    vki.* = try InstanceDispatch.load(instance, base_dispatch.dispatch.vkGetInstanceProcAddr);
    const vulkan_instance = Instance.init(instance, vki);
    errdefer vulkan_instance.destroyInstance(null);

    // Clean up resources
    vulkan_instance.destroyInstance(null);
    allocator.destroy(vulkan_instance.wrapper);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    // const window = try zglfw.createWindow(1280, 720, window_title, null);
    // defer zglfw.destroyWindow(window);

    try initVulkan(allocator);

    // while (!window.shouldClose()) {
    //     zglfw.pollEvents();
    //     window.swapBuffers();
    // }
}

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
