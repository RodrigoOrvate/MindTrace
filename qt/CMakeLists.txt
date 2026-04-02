cmake_minimum_required(VERSION 3.12)
project(MindTrace VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Avisa ao VS Code exatamente onde o Qt está instalado
set(CMAKE_PREFIX_PATH "C:/Qt/Qt5.12.12/5.12.12/msvc2017_64")
set(Qt5_DIR "C:/Qt/Qt5.12.12/5.12.12/msvc2017_64/lib/cmake/Qt5")

# Qt 5.12 LTS — última versão com suporte oficial ao Windows 7
find_package(Qt5 5.12 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)

qt5_add_resources(QRC_SOURCES resources.qrc)

add_executable(MindTrace WIN32
    "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ExperimentManager.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ExperimentManager.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/ExperimentTableModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ExperimentTableModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/ArenaModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ArenaModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/ArenaConfigModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ArenaConfigModel.h"
    "${QRC_SOURCES}"
)

target_link_libraries(MindTrace PRIVATE
    Qt5::Core
    Qt5::Widgets
    Qt5::Quick
    Qt5::QuickControls2
    Qt5::Multimedia
)
