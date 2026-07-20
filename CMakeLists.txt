cmake_minimum_required(VERSION 3.16)

project(osc_recorder VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(QT_QML_GENERATE_QMLLS_INI ON)

find_package(Qt6 REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES 6.8)

# Content of downloaded design from Figma to Qt or similar
if (EXISTS "${CMAKE_CURRENT_LIST_DIR}/importedcontent/CMakeLists.txt")
    add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/importedcontent)
endif()

qt_add_executable(apposc_recorder
    main.cpp
)

qt_add_qml_module(apposc_recorder
    URI osc_recorder
    QML_FILES
        Main.qml
        ChannelStore.qml
        NavigationPanel.qml
        WaveformPanel.qml
        ParameterPanel.qml
        ChannelSettingsPage.qml
        AcquisitionSettingsPage.qml
        RecordingPage.qml
        SystemStatusPage.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(apposc_recorder PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.apposc_recorder
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(apposc_recorder
    PRIVATE Qt6::Quick
)

install(TARGETS apposc_recorder
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
