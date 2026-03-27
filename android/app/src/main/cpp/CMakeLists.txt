cmake_minimum_required(VERSION 3.18.1)
project(sequencer_native)

add_library(
    sequencer_native
    SHARED
    sequencer_native.cpp
)

find_library(log-lib log)
find_library(z-lib z)

target_compile_features(sequencer_native PUBLIC cxx_std_17)

target_compile_options(sequencer_native PRIVATE
    -O3
    -DNDEBUG
    -fvisibility=hidden
)

target_link_libraries(
    sequencer_native
    ${log-lib}
    ${z-lib}
)
