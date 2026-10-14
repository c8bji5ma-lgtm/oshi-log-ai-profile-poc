# Do not retain private source images in libvips' cross-request operation cache.
require "vips"
Vips.cache_set_max(0)
