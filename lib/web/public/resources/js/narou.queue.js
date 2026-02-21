/* -*- coding: utf-8 -*-
 *
 * Copyright 2013 whiteleaf. All rights reserved.
 */

/*
 * キュー関係のコード
 */
$(function() {
  "use strict";

  /*
   * キューに積まれた数を表示
   */
  var notification = Narou.Notification.instance();
  var $queue = $(".queue");
  var $queueSizes = $(".queue__sizes");
  var $queueSizeDefault = $(".queue__size--default");
  var $queueSizeConvert = $(".queue__size--convert");

  function highlightQueuBoxIcon(sizes) {
    if (sizes[0] || sizes[1]) {
      $queue.addClass("active");
    }
    else {
      $queue.removeClass("active");
    }
  }

  function setQueueSizesText(sizes) {
    $queueSizeDefault.text(sizes[0]);
    if (Narou.concurrencyIsEnabled()) {
      $queueSizeConvert.text(sizes[1]);
    }
    highlightQueuBoxIcon(sizes);
  }

  notification.on("notification.queue", function(sizes) {
    setQueueSizesText(sizes);
  });

  notification.on("queue.pending_running_tasks", function(tasks) {
    if (!tasks || tasks.length === 0) return;
    var taskList = tasks.map(function(t) {
      var cmd = (t && (t.cmd || t["cmd"] || t.command)) || "unknown";
      var args = (t && (t.args || t["args"])) || [];
      return cmd + " " + args.join(" ");
    }).join("\n");
    var message = "前回中断されたタスクが" + tasks.length + "件あります:\n" + taskList + "\n\n再実行しますか？";
    if (confirm(message)) {
      $.post("/api/confirm_running_tasks", { rerun: "true" });
    } else {
      $.post("/api/confirm_running_tasks", { rerun: "false" });
    }
  });

  $.get("/api/get_queue_size", function(sizes) {
    setQueueSizesText(sizes);
  });

  $.get("/api/get_pending_tasks", function(data) {
    if (data.waiting_confirmation && data.running && data.running.length > 0) {
      notification.trigger("queue.pending_running_tasks", [data.running]);
    }
  });
});
