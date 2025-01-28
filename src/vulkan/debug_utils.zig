const std = @import("std");
const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");

const BaseDispatcher = vulkan.BaseDispatcher;
const InstanceDispatcher = vulkan.InstanceDispatcher;

const severity_info = vk.DebugUtilsMessageSeverityFlagsEXT{ .info_bit_ext = true };
const severity_erro = vk.DebugUtilsMessageSeverityFlagsEXT{ .error_bit_ext = true };
const severity_warn = vk.DebugUtilsMessageSeverityFlagsEXT{ .warning_bit_ext = true };
const severity_verb = vk.DebugUtilsMessageSeverityFlagsEXT{ .verbose_bit_ext = true };

pub fn CreateDefaultDebugUtilsCreateInfo() vk.DebugUtilsMessengerCreateInfoEXT {
    const ci: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .s_type = vk.StructureType.debug_utils_messenger_create_info_ext,
        .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
            .warning_bit_ext = true,
            .info_bit_ext = true,
            .error_bit_ext = true,
            .verbose_bit_ext = true,
        },
        .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugCallBack,
        .p_user_data = null,
    };

    return ci;
}

pub fn createDebugUtilsMessenger(
    base_dispatcher: BaseDispatcher,
    instance: vk.Instance,
    create_info: *vk.DebugUtilsMessengerCreateInfoEXT,
    debug_messenger: *vk.DebugUtilsMessengerEXT,
) void {
    const func: vk.PfnCreateDebugUtilsMessengerEXT = @ptrCast(base_dispatcher.getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    _ = func(instance, create_info, null, debug_messenger);
}

pub fn destroyDebugUtilsMessenger(base_dispatcher: BaseDispatcher, instance: vk.Instance, debug_messenger: vk.DebugUtilsMessengerEXT) void {
    const func: vk.PfnDestroyDebugUtilsMessengerEXT = @ptrCast(base_dispatcher.getInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    _ = func(instance, debug_messenger, null);
}

fn debugCallBack(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    cb_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    // TODO: Do something with this data....
    _ = message_type;
    _ = user_data;

    const data = cb_data orelse null;
    if (data == null) {
        return vk.FALSE;
    }

    const message_severity = severity.toInt();
    switch (message_severity) {
        0...severity_info.toInt() => {
            std.log.info("{?s}", .{data.?.p_message});
        },
        severity_info.toInt() + 1...severity_warn.toInt() => {
            std.log.warn("{?s}", .{data.?.p_message});
        },
        severity_warn.toInt() + 1...severity_erro.toInt() => {
            std.log.err("{?s}", .{data.?.p_message});
        },
        else => {
            std.log.info("{?s}", .{data.?.p_message});
        },
    }

    // Application code should always return VK_FALSE
    return vk.FALSE;
}
