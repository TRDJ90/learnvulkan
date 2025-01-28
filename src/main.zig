const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const vulkan = @import("vulkan/vulkan.zig");
const DebugUtils = @import("vulkan/debug_utils.zig");

const window_title = "Learn webgpu";

fn pickPhyiscalDevice() void {}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    // const window = try zglfw.createWindow(1280, 720, window_title, null);
    // defer zglfw.destroyWindow(window);

    // try initVulkan(allocator);

    var window_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 8);
    defer window_extensions.deinit();

    const glfw_extensions = try zglfw.getRequiredInstanceExtensions();
    for (glfw_extensions) |ext| {
        try window_extensions.append(ext);
    }

    const vk_ctx = try vulkan.VulkanContext.initDefault(allocator, window_extensions);
    vk_ctx.deinit();
    // while (!window.shouldClose()) {
    //     zglfw.pollEvents();
    //     window.swapBuffers();
    // }
}
