# typed: false
# frozen_string_literal: true

require "macho"

module Hardware
  class CPU
    class << self
      undef type, family, universal_archs, features, sse4?

      # These methods use info spewed out by sysctl.
      # Look in <mach/machine.h> for decoding info.
      def type
        case sysctl_int("hw.cputype")
        when MachO::Headers::CPU_TYPE_I386
          :intel
        when MachO::Headers::CPU_TYPE_ARM64
          :arm
        else
          :dunno
        end
      end

      def family
        case sysctl_int("hw.cpufamily")
        when 0x73d67300 # Yonah: Core Solo/Duo
          :core
        when 0x426f69ef # Merom: Core 2 Duo
          :core2
        when 0x78ea4fbc # Penryn
          :penryn
        when 0x6b5a4cd2 # Nehalem
          :nehalem
        when 0x573B5EEC # Arrandale
          :arrandale
        when 0x5490B78C # Sandy Bridge
          :sandybridge
        when 0x1F65E835 # Ivy Bridge
          :ivybridge
        when 0x10B282DC # Haswell
          :haswell
        when 0x582ed09c # Broadwell
          :broadwell
        when 0x37fc219f # Skylake
          :skylake
        when 0x0f817246 # Kaby Lake
          :kabylake
        when 0x38435547 # Ice Lake
          :icelake
        when 0x07d34b9f # ARMv8.3-A (Vortex, Tempest)
          :arm_vortex_tempest
        else
          :dunno
        end
      end

      # Returns an array that's been extended with {ArchitectureListExtension},
      # which provides helpers like `#as_arch_flags`.
      def universal_archs
        # Amazingly, this order (64, then 32) matters. It shouldn't, but it
        # does. GCC (some versions? some systems?) can blow up if the other
        # order is used.
        # https://superuser.com/questions/740563/gcc-4-8-on-macos-fails-depending-on-arch-order
        [arch_64_bit, arch_32_bit].extend ArchitectureListExtension
      end

      # True when running under an Intel-based shell via Rosetta 2 on an
      # Apple Silicon Mac. This can be detected via seeing if there's a
      # conflict between what `uname` reports and the underlying `sysctl` flags,
      # since the `sysctl` flags don't change behaviour under Rosetta 2.
      def in_rosetta2?
        intel? && physical_cpu_arm64?
      end

      def features
        @features ||= sysctl_n(
          "machdep.cpu.features",
          "machdep.cpu.extfeatures",
          "machdep.cpu.leaf7_features",
        ).split(" ").map { |s| s.downcase.to_sym }
      end

      def sse4?
        sysctl_bool("hw.optional.sse4_1")
      end

      def extmodel
        sysctl_int("machdep.cpu.extmodel")
      end

      def aes?
        sysctl_bool("hw.optional.aes")
      end

      def altivec?
        sysctl_bool("hw.optional.altivec")
      end

      def avx?
        sysctl_bool("hw.optional.avx1_0")
      end

      def avx2?
        sysctl_bool("hw.optional.avx2_0")
      end

      def sse3?
        sysctl_bool("hw.optional.sse3")
      end

      def ssse3?
        sysctl_bool("hw.optional.supplementalsse3")
      end

      def sse4_2?
        sysctl_bool("hw.optional.sse4_2")
      end

      # Note: this is more reliable than checking uname.
      # `sysctl` returns the right answer even when running in Rosetta 2.
      def physical_cpu_arm64?
        sysctl_bool("hw.optional.arm64")
      end

      private

      def sysctl_bool(key)
        sysctl_int(key) == 1
      end

      def sysctl_int(key)
        sysctl_n(key).to_i
      end

      def sysctl_n(*keys)
        (@properties ||= {}).fetch(keys) do
          @properties[keys] = Utils.popen_read("/usr/sbin/sysctl", "-n", *keys)
        end
      end
    end
  end
end
