/**
 * HTML scheduler for ATCA and Parkes.
 * Jamie Stevens 2019
 */

const printDate = function(d) {
  var m = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ];
  var w = [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ];
  var r = w[d.getDay()] + " " + m[d.getMonth()] + " " + d.getDate();
  return r;
};

// Some necessary measurements.
var halfHourWidth = 12;
var margin = 60;
var elementWidth = 300;
var dayHeight = 40;
var dayLabelWidth = 140;
var dayWidth = 48 * halfHourWidth;

var nDays = (366 / 2) + 4;

// Set up the schedule.
var semester = "APR";
var year = 2019;

// Get the date for the first day of the schedule.
var semesterStart = new Date();
var semesterStartMonth = -1;
if (semester == "APR") {
  semesterStartMonth = 4;
} else if (semester == "OCT") {
  semesterStartMonth = 10;
}
semesterStart.setFullYear(year, (semesterStartMonth - 1), 1);
// Subtract a few days.
var scheduleFirst = new Date();
scheduleFirst.setTime(semesterStart.getTime() - 3 * 86400 * 1000);
// Make all the dates.
var allDates = [];
for (var i = 0; i < nDays; i++) {
  var pdate = new Date();
  pdate.setTime(scheduleFirst.getTime() + i * 86400 * 1000);
  allDates.push(pdate);
}


// Set up the canvas.
var width = dayWidth + 3 * margin + elementWidth + dayLabelWidth;
var height = nDays * dayHeight + 2 * margin;
var stage = new Konva.Stage({
  container: "schedtable",
  width: width, height: height
});

var shapesLayer = new Konva.Layer();
var scheduleGroup = new Konva.Group({
  draggable: false
});

for (var i = 0; i < nDays; i++) {
  // The date is shown in the day label box.
  var dayLabelBox = new Konva.Rect({
    x: margin, y: (margin + i * dayHeight),
    width: dayLabelWidth, height: dayHeight,
    stroke: "black", strokeWidth: 2
  });
  // Make the string.
  var dateString = new Konva.Text({
    x: margin + 5, y: (margin + i * dayHeight + 5),
    text: printDate(allDates[i]), fontSize: 20
  });
  var dayBox = new Konva.Rect({
    x: margin + dayLabelWidth, y: (margin + i * dayHeight),
    width: dayWidth, height: dayHeight,
    stroke: "black", strokeWidth: 2
  });
  scheduleGroup.add(dayLabelBox);
  scheduleGroup.add(dateString);
  scheduleGroup.add(dayBox);

  // Draw an hour grid.
  for (var j = 0; j < 24; j++) {
    fillColour = "#00aa00";
    if (j % 2) {
      fillColour = "#ffffff";
    }
    var hourRect = new Konva.Rect({
      x: (margin + dayLabelWidth + j * 2 * halfHourWidth),
      y: (margin + i * dayHeight + 1),
      width: (2 * halfHourWidth), height: (dayHeight - 2),
      fill: fillColour, stroke: fillColour, strokeWidth: 0
    });
    scheduleGroup.add(hourRect);
  }

  // Draw the hour labels at the top.
  if (i == 0) {
    for (var j = 0; j <= 24; j += 2) {
      var hourLabel = new Konva.Text({
	x: (margin + dayLabelWidth + j * 2 * halfHourWidth),
	y: (margin), text: "" + (j % 24), fontSize: 20
      });
      hourLabel.offsetX(hourLabel.width() / 2);
      hourLabel.offsetY(hourLabel.height() * 1.1);
      scheduleGroup.add(hourLabel);
      var utcLabel = new Konva.Text({
	x: (margin + dayLabelWidth + j * 2 * halfHourWidth),
	y: margin, text: "" + ((j + 14) % 24), fontSize: 20
      });
      utcLabel.offsetX(utcLabel.width() / 2);
      utcLabel.offsetY(utcLabel.height() * 2.2);
      scheduleGroup.add(utcLabel);
    }
  }
}
shapesLayer.add(scheduleGroup);
stage.add(shapesLayer);

