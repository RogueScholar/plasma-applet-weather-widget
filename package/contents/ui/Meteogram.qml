/*
 * Copyright 2015  Martin Kotelnik <clearmartin@seznam.cz>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http: //www.gnu.org/licenses/>.
 */

import QtQuick 2.2
import QtQuick.Layouts 1.1
import QtGraphicalEffects 1.0

import org.kde.plasma.components 2.0 as PlasmaComponents

import "../code/unit-utils.js" as UnitUtils
import "../code/icons.js" as IconTools

Item {
    id: meteogram

    property bool enableRendering: renderMeteogram || currentProvider.providerId !== 'yrno'

    property int temperatureSizeY: 21
    property int pressureSizeY: 101
    property int pressureMultiplier: Math.round((pressureSizeY - 1) / (temperatureSizeY - 1))

    property int graphLeftMargin: 28 * units.devicePixelRatio
    property int graphTopMargin: 20 * units.devicePixelRatio
    property double graphWidth: meteogram.width - graphLeftMargin * 2
    property double graphHeight: meteogram.height - graphTopMargin * 2
    property double topBottomCanvasMargin: (graphHeight / temperatureSizeY) * 0.5

    property int hourModelSize: 0

    property var dataArray: []

    property int dataArraySize: 2
    property double sampleWidth: graphWidth / (dataArraySize - 1)

    property double temperatureAdditiveY: 0
    property double temperatureMultiplierY: graphHeight / (temperatureSizeY - 1)

    property int pressureAdditiveY: - 950
    property double pressureMultiplierY: graphHeight / (pressureSizeY - 1)

    property bool meteogramModelChanged: main.meteogramModelChanged

    property int precipitationFontPixelSize: 8 * units.devicePixelRatio
    property int precipitationHeightMultiplier: 15 * units.devicePixelRatio
    property int precipitationLabelMargin: 10 * units.devicePixelRatio

    property bool textColorLight: ((theme.textColor.r + theme.textColor.g + theme.textColor.b) / 3) > 0.5
    property color gridColor: textColorLight ? Qt.tint(theme.textColor, '#80000000') : Qt.tint(theme.textColor, '#80FFFFFF')
    property color gridColorHighlight: textColorLight ? Qt.tint(theme.textColor, '#50000000') : Qt.tint(theme.textColor, '#50FFFFFF')
    property color gridCursorColor: textColorLight ? "white" : "black"

    property color pressureColor: textColorLight ? Qt.rgba(0.3, 1, 0.3, 1) : Qt.rgba(0.0, 0.6, 0.0, 1)
    property color temperatureWarmColor: textColorLight ? Qt.rgba(1, 0.3, 0.3, 1) : Qt.rgba(1, 0.0, 0.0, 1)
    property color temperatureColdColor: textColorLight ? Qt.rgba(0.2, 0.7, 1, 1) : Qt.rgba(0.1, 0.5, 1, 1)

    onMeteogramModelChangedChanged: {
        dbgprint('meteogram changed')
        modelUpdated()
    }

    function _appendHorizontalModel(meteogramModelObj) {
        var oneHourMs = 3600000
        var dateFrom = meteogramModelObj.from
        // floor to hours
        dateFrom.setMilliseconds(0)
        dateFrom.setSeconds(0)
        dateFrom.setMinutes(0)
        var dateTo = meteogramModelObj.to
        var differenceHours = Math.round((dateTo.getTime() - dateFrom.getTime()) / oneHourMs)
        dbgprint('differenceHours=' + differenceHours + ', oneHourMs=' + oneHourMs + ', dateFrom=' + dateFrom + ', dateTo=' + dateTo)
        if (differenceHours > 20) {
            return
        }
        var differenceHoursMid = Math.ceil(differenceHours / 2) - 1
        dbgprint('differenceHoursMid=' + differenceHoursMid)
        for (var i = 0; i < differenceHours; i++) {
            var preparedDate = new Date(dateFrom.getTime() + i * oneHourMs)
            hourGridModel.append({
                dateFrom: UnitUtils.convertDate(preparedDate, timezoneType),
                iconName: i === differenceHoursMid ? meteogramModelObj.iconName : '',
                temperature: meteogramModelObj.temperature,
                precipitationAvg: meteogramModelObj.precipitationAvg,
                precipitationMin: meteogramModelObj.precipitationMin,
                precipitationMax: meteogramModelObj.precipitationMax,
                canShowDay: true,
                canShowPrec: true,
                differenceHours: differenceHours
            })
        }
    }

    function _adjustLastDay() {
        for (var i = hourGridModel.count - 5; i < hourGridModel.count; i++) {
            hourGridModel.setProperty(i, 'canShowDay', false)
        }
        hourGridModel.setProperty(hourGridModel.count - 1, 'canShowPrec', false)
    }

    function clearCanvas() {
        temperaturePathWarm.pathElements = []
        temperaturePathCold.pathElements = []
        pressurePath.pathElements = []
        repaintCanvas()
    }

    function repaintCanvas() {
        meteogramCanvasWarmTemp.requestPaint()
        meteogramCanvasColdTemp.requestPaint()
        meteogramCanvasPressure.requestPaint()
    }

    function modelUpdated() {

        dbgprint('meteogram model updated ' + meteogramModel.count)
        dataArraySize = meteogramModel.count

        if (dataArraySize === 0) {
            dbgprint('model is empty -> clearing canvas and exiting')
            clearCanvas()
            return
        }

        hourGridModel.clear()

        var minValue = null
        var maxValue = null

        for (var i = 0; i < dataArraySize; i++) {
            var obj = meteogramModel.get(i)
            _appendHorizontalModel(obj)
            var value = obj.temperature
            if (minValue === null) {
                minValue = value
                maxValue = value
                continue
            }
            if (value < minValue) {
                minValue = value
            }
            if (value > maxValue) {
                maxValue = value
            }
        }

        _adjustLastDay()

        dbgprint('minValue: ' + minValue)
        dbgprint('maxValue: ' + maxValue)
        dbgprint('temperatureSizeY: ' + temperatureSizeY)

        var mid = (maxValue - minValue) / 2 + minValue
        var halfSize = temperatureSizeY / 2

        temperatureAdditiveY = Math.round(- (mid - halfSize))

        dbgprint('temperatureAdditiveY: ' + temperatureAdditiveY)

        redrawCanvas()
    }

    function redrawCanvas() {

        dbgprint('redrawing canvas with temperatureMultiplierY=' + temperatureMultiplierY)

        var newPathElements = []
        var newPressureElements = []

        if (dataArraySize === 0 || temperatureMultiplierY > 1000000 || temperatureMultiplierY === 0) {
            return
        }

        for (var i = 0; i < dataArraySize; i++) {
            var dataObj = meteogramModel.get(i)

            dbgprint('hour: ' + dataObj.from)

            var rawTempY = temperatureSizeY - (dataObj.temperature + temperatureAdditiveY)
            dbgprint('realTemp: ' + dataObj.temperature + ', rawTempY: ' + rawTempY)
            var temperatureY = rawTempY * temperatureMultiplierY

            var rawPressY = pressureSizeY - (dataObj.pressureHpa + pressureAdditiveY)
            dbgprint('realPress: ' + dataObj.pressureHpa + ', rawPressY: ' + rawPressY)
            var pressureY = rawPressY * pressureMultiplierY

            dbgprint('icon: ' + dataObj.iconName)

            if (i === 0) {
                temperaturePathWarm.startY = temperatureY
                temperaturePathCold.startY = temperatureY
                pressurePath.startY = pressureY
                continue
            }

            newPathElements.push(Qt.createQmlObject('import QtQuick 2.0; PathCurve { x: ' + (i * sampleWidth) + '; y: ' + temperatureY + ' }', meteogram, "dynamicTemperature" + i))

            newPressureElements.push(Qt.createQmlObject('import QtQuick 2.0; PathCurve { x: ' + (i * sampleWidth) + '; y: ' + pressureY + ' }', meteogram, "dynamicPressure" + i))
        }

        temperaturePathWarm.pathElements = newPathElements
        temperaturePathCold.pathElements = newPathElements
        pressurePath.pathElements = newPressureElements

        repaintCanvas()

    }

    function precipitationFormat(precFloat) {
        if (precFloat >= 0.1) {
            var result = Math.round(precFloat * 10) / 10
            dbgprint('precipitationFormat returns ' + result)
            return String(result)
        }
        return ''
    }

    ListModel {
        id: verticalGridModel
    }

    ListModel {
        id: hourGridModel
    }

    Component.onCompleted: {
        for (var i = 0; i < temperatureSizeY; i++) {
            verticalGridModel.append({
                num: i
            })
        }
        modelUpdated()
    }

    Item {
        id: graph
        width: graphWidth
        height: graphHeight
        anchors.centerIn: parent
        anchors.topMargin: -(graphHeight / temperatureSizeY) * 0.5

        visible: enableRendering

        ListView {
            id: horizontalLines
            model: verticalGridModel
            anchors.fill: parent

            interactive: false

            delegate: Item {
                height: horizontalLines.height / (temperatureSizeY - 1)
                width: horizontalLines.width

                visible: num % 2 === 0

                Rectangle {
                    width: parent.width
                    height: 1 * units.devicePixelRatio
                    color: gridColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                PlasmaComponents.Label {
                    text: UnitUtils.getTemperatureNumberExt(-temperatureAdditiveY + (temperatureSizeY - num), temperatureType)
                    height: parent.height
                    width: graphLeftMargin - 2 * units.devicePixelRatio
                    horizontalAlignment: Text.AlignRight
                    anchors.left: parent.left
                    anchors.leftMargin: -graphLeftMargin
                    font.pixelSize: 11 * units.devicePixelRatio
                    font.pointSize: -1
                }

                PlasmaComponents.Label {
                    text: String(UnitUtils.getPressureNumber(-pressureAdditiveY + (pressureSizeY - 1 - num * pressureMultiplier), pressureType))
                    height: parent.height
                    width: graphLeftMargin - 2 * units.devicePixelRatio
                    horizontalAlignment: Text.AlignLeft
                    anchors.right: parent.right
                    anchors.rightMargin: -graphLeftMargin
                    font.pixelSize: 11 * units.devicePixelRatio
                    font.pointSize: -1
                    color: pressureColor
                }

                PlasmaComponents.Label {
                    text: UnitUtils.getPressureEnding(pressureType)
                    height: parent.height
                    width: graphLeftMargin - 2 * units.devicePixelRatio
                    horizontalAlignment: Text.AlignLeft
                    anchors.right: parent.right
                    anchors.rightMargin: -graphLeftMargin
                    font.pixelSize: 11 * units.devicePixelRatio
                    font.pointSize: -1
                    color: pressureColor
                    anchors.top: parent.top
                    anchors.topMargin: -14 * units.devicePixelRatio
                    visible: num === 0
                }
            }
        }

        ListView {
            id: hourGrid
            model: hourGridModel

            property double hourItemWidth: hourGridModel.count === 0 ? 0 : parent.width / (hourGridModel.count - 1)

            width: hourItemWidth * hourGridModel.count
            height: parent.height

            anchors.fill: parent
            anchors.topMargin: -graph.anchors.topMargin
            anchors.bottomMargin: graph.anchors.topMargin
            anchors.leftMargin: -(hourItemWidth / 2)
            orientation: ListView.Horizontal

            interactive: false

            delegate: Item {
                height: hourGrid.height
                width: hourGrid.hourItemWidth

                property int hourFrom: dateFrom.getHours()
                property string hourFromStr: UnitUtils.getHourText(hourFrom, twelveHourClockEnabled)
                property string hourFromEnding: twelveHourClockEnabled ? UnitUtils.getAmOrPm(hourFrom) : '00'
                property bool dayBegins: hourFrom === 0
                property bool hourVisible: hourFrom % 2 === 0
                property bool textVisible: hourVisible && index < hourGridModel.count-1
                property int timePeriod: hourFrom >= 6 && hourFrom <= 18 ? 0 : 1

                property double precAvg: parseFloat(precipitationAvg) || 0
                property double precMax: parseFloat(precipitationMax) || 0

                property bool precLabelVisible: precAvg >= 0.1 || precMax >= 0.1

                property string precAvgStr: precipitationFormat(precAvg)
                property string precMaxStr: precipitationFormat(precMax)

                PlasmaComponents.Label {
                    id: dayTest
                    text: Qt.locale().dayName(dateFrom.getDay(), Locale.LongFormat)
                    height: graphTopMargin - 2 * units.devicePixelRatio
                    anchors.top: parent.top
                    anchors.topMargin: -graphTopMargin
                    anchors.left: parent.left
                    anchors.leftMargin: parent.width / 2
                    font.pixelSize: 11 * units.devicePixelRatio
                    font.pointSize: -1
                    visible: dayBegins && canShowDay
                }

                Rectangle {
                    width: dayBegins ? 2 : 1
                    height: parent.height
                    color: dayBegins ? gridColorHighlight : gridColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: hourVisible
                }

                PlasmaComponents.Label {
                    id: hourText
                    text: hourFromStr
                    verticalAlignment: Text.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                    height: graphTopMargin - 2 * units.devicePixelRatio
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -graphTopMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: 11 * units.devicePixelRatio
                    font.pointSize: -1
                    visible: textVisible
                }

                PlasmaComponents.Label {
                    text: hourFromEnding
                    verticalAlignment: Text.AlignTop
                    horizontalAlignment: Text.AlignLeft
                    anchors.top: hourText.top
                    anchors.left: hourText.right
                    font.pixelSize: 7 * units.devicePixelRatio
                    font.pointSize: -1
                    visible: textVisible
                }

                PlasmaComponents.Label {
                    font.pixelSize: 14 * units.devicePixelRatio
                    font.pointSize: -1

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: (temperatureSizeY - (temperature + temperatureAdditiveY)) * temperatureMultiplierY - font.pixelSize * 2.5

                    font.family: 'weathericons'
                    //text: textVisible || index === 0 || iconName === '' ? '' : IconTools.getIconCode(iconName, currentProvider.providerId, timePeriod)
                    text: (differenceHours === 1 && textVisible) || index === hourGridModel.count-1 || index === 0 || iconName === '' ? '' : IconTools.getIconCode(iconName, currentProvider.providerId, timePeriod)
                }

                Item {
                    visible: canShowPrec
                    anchors.fill: parent

                    Rectangle {
                        id: precipitationMaxRect
                        width: parent.width
                        height: (precMax < precAvg ? precAvg : precMax) * precipitationHeightMultiplier
                        color: theme.highlightColor
                        anchors.left: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: precipitationLabelMargin
                        opacity: 0.5
                    }

                    Rectangle {
                        id: precipitationAvgRect
                        width: parent.width
                        height: precAvg * precipitationHeightMultiplier
                        color: theme.highlightColor
                        anchors.left: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: precipitationLabelMargin
                    }

                    PlasmaComponents.Label {
                        text: precipitationMin
                        verticalAlignment: Text.AlignTop
                        horizontalAlignment: Text.AlignHCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: -precipitationLabelMargin
                        anchors.horizontalCenter: precipitationAvgRect.horizontalCenter
                        font.pixelSize: precipitationFontPixelSize
                        font.pointSize: -1
                        visible: precLabelVisible
                    }

                    PlasmaComponents.Label {
                        text: precMaxStr || precAvgStr
                        verticalAlignment: Text.AlignBottom
                        horizontalAlignment: Text.AlignHCenter
                        anchors.bottom: precipitationMaxRect.top
                        anchors.horizontalCenter: precipitationAvgRect.horizontalCenter
                        font.pixelSize: precipitationFontPixelSize
                        font.pointSize: -1
                        visible: precLabelVisible
                    }
                }

            }
        }

        Item {
            id: canvases
            anchors.fill: parent
            anchors.topMargin: topBottomCanvasMargin

            Canvas {
                id: meteogramCanvasPressure
                anchors.fill: parent
                contextType: '2d'

                Path {
                    id: pressurePath
                    startX: 0
                }

                onPaint: {
                    context.clearRect(0, 0, width, height)

                    context.strokeStyle = pressureColor
                    context.lineWidth = 1 * units.devicePixelRatio;
                    context.path = pressurePath
                    context.stroke()
                }
            }

            Canvas {
                id: meteogramCanvasWarmTemp
                anchors.top: parent.top
                width: parent.width
                height: parent.height - temperatureMultiplierY * (temperatureAdditiveY - 1) + topBottomCanvasMargin

                onWidthChanged: {
                    meteogramCanvasWarmTemp.requestPaint()
                }

                contextType: '2d'

                Path {
                    id: temperaturePathWarm
                    startX: 0
                }

                onPaint: {
                    context.clearRect(0, 0, width, height)

                    context.strokeStyle = temperatureWarmColor
                    context.lineWidth = 2 * units.devicePixelRatio;
                    context.path = temperaturePathWarm
                    context.stroke()
                }
            }

            Item {

                anchors.fill: parent
                anchors.topMargin: meteogramCanvasWarmTemp.height
                clip: true

                Canvas {
                    id: meteogramCanvasColdTemp
                    anchors.top: parent.top
                    width: graphWidth
                    height: graphHeight
                    anchors.topMargin: - parent.anchors.topMargin
                    contextType: '2d'

                    Path {
                        id: temperaturePathCold
                        startX: 0
                    }

                    onPaint: {
                        context.clearRect(0, 0, width, height)

                        context.strokeStyle = temperatureColdColor
                        context.lineWidth = 2 * units.devicePixelRatio;
                        context.path = temperaturePathCold
                        context.stroke()
                    }
                }
            }

            // Temperature Cursor
            Item {
                property color cursorColor: pathInterpolator.y <= meteogramCanvasWarmTemp.height ? temperatureWarmColor : temperatureColdColor

                id: cursor
                anchors.fill: parent
                anchors.bottomMargin: -topBottomCanvasMargin
                opacity: 0.0

                Behavior on opacity {
                    PropertyAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }

                Behavior on cursorColor {
                    PropertyAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }

                Connections {
                    target: pathInterpolator
                    onProgressChanged: cursor.opacity = 1.0
                }

                Timer {
                    id: hideTimer
                    interval: 3000
                    running: !cursorArea.pressed

                    onTriggered: {
                        cursor.opacity = 0.0
                    }
                }

                Rectangle {
                    id: baseline
                    color: gridCursorColor
                    width: parent.width
                    height: 1
                    x: 0
                    y: meteogramCanvasWarmTemp.height
                }

                Rectangle {
                    id: timeLine
                    color: gridCursorColor
                    width: 1
                    x: pathInterpolator.x - width / 2.0
                    anchors.bottom: parent.bottom
                    anchors.top: parent.top
                }

                Item {
                    anchors.fill: parent
                    clip: true
                    Rectangle {
                        id: temperatureLine
                        color: cursor.cursorColor
                        width: 1
                        height: Math.abs(meteogramCanvasWarmTemp.height - pathInterpolator.y)
                        x: pathInterpolator.x - width / 2.0
                        y: pathInterpolator.y <= meteogramCanvasWarmTemp.height ? pathInterpolator.y : meteogramCanvasWarmTemp.height
                    }
                }

                Rectangle {
                    id: dot
                    color: cursor.cursorColor
                    width: 8
                    height: width
                    radius: width / 2.0
                    x: pathInterpolator.x - width / 2.0
                    y: pathInterpolator.y - width / 2.0
                }

                PlasmaComponents.Label {
                    readonly property point offset: Qt.point(28, -28)

                    id: temperatureText
                    color: "white"
                    text: UnitUtils.getTemperature(-10.0 * ((pathInterpolator.y / temperatureMultiplierY) - temperatureSizeY + temperatureAdditiveY) / 10.0, temperatureType).toFixed(1) + UnitUtils.getTemperatureEnding(temperatureType)

                    x: Math.min(pathInterpolator.x - width / 2.0 + offset.x, parent.width - width)
                    y: pathInterpolator.y - height / 2.0 + offset.y

                    Rectangle {
                        id: textBackground
                        anchors.centerIn: parent
                        color: "black"
                        opacity: 0.6
                        radius: 3
                        z: -1

                        width: parent.implicitWidth + 8
                        height: parent.implicitHeight + 8
                    }
                }

                PathInterpolator {
                    id: pathInterpolator
                    path: temperaturePathWarm
                }

                MouseArea {
                    id: cursorArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton

                    onPositionChanged: pathInterpolator.progress = mouse.x / width
                    onPressed: pathInterpolator.progress = mouse.x / width
                }
            }
        }
    }

    Item {

        anchors.fill: parent

        visible: !enableRendering

        PlasmaComponents.Label {
            id: noImageText
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.top: parent.top
            anchors.topMargin: headingHeight
            text: loadingError ? i18n('Offline mode') : i18n('Loading image...')
        }

        Image {
            id: overviewImage
            cache: false
            source: !enableRendering ? overviewImageSource : undefined
            anchors.fill: parent
        }

        states: [
            State {
                name: 'error'
                when: !enableRendering && (overviewImage.status == Image.Error || overviewImage.status == Image.Null)

                StateChangeScript {
                    script: {
                        dbgprint('image loading error')
                        imageLoadingError = true
                    }
                }
            },
            State {
                name: 'loading'
                when: !enableRendering && (overviewImage.status == Image.Loading || overviewImage.status == Image.Ready)

                StateChangeScript {
                    script: {
                        imageLoadingError = false
                    }
                }
            }
        ]

    }

}
