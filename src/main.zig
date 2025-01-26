const std = @import("std");
const zglfw = @import("zglfw");

const window_title = "Learn webgpu";

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.createWindow(1280, 720, window_title, null);
    defer zglfw.destroyWindow(window);

    std.log.info("Vulkan supported: {}", .{zglfw.isVulkanSupported()});

    const extensions = try zglfw.getRequiredInstanceExtensions();
    for (extensions) |ext| {
        std.log.info("{s}", .{ext});
    }

    while (!window.shouldClose()) {
        zglfw.pollEvents();
        window.swapBuffers();
    }
}
