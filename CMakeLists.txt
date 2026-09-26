cmake_minimum_required(VERSION 3.16)

project(ludus
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

file(GLOB_RECURSE LUDUS_SOURCES
    CONFIGURE_DEPENDS
    ${PROJECT_SOURCE_DIR}/src/*.cpp
)

add_library(ludus STATIC ${LUDUS_SOURCES})

target_include_directories(ludus
    PUBLIC
        ${PROJECT_SOURCE_DIR}/include
)