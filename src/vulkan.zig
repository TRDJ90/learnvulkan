const vk = @import("vulkan");

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

pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);

pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
