/* -*- coding: utf-8 -*-
 *
 * Copyright 2013 whiteleaf. All rights reserved.
 */

/*
 * キュー関係のコード
 */
$(function() {
  "use strict";

  var notification = Narou.Notification.instance();
  var $queue = $(".queue");
  var $queueSizeDefault = $(".queue__size--default");
  var $queueSizeConvert = $(".queue__size--convert");
  var queueModalId = "queue-manager-modal";
  var draggingTaskId = null;
  var commandNames = {
    download: "ダウンロード",
    download_force: "強制ダウンロード",
    update: "更新",
    update_by_tag: "更新",
    update_general_lastup: "最新話掲載日更新",
    auto_update: "自動アップデート",
    convert: "変換",
    mail: "メール送信",
    send: "端末送信",
    freeze: "凍結",
    remove: "削除",
    backup: "バックアップ",
    inspect: "inspect",
    diff: "差分確認",
    diff_clean: "差分確認(clean)",
    setting_burn: "設定焼き込み",
    backup_bookmark: "しおりバックアップ",
    eject: "端末の取り外し"
  };

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

  function escapeHtml(text) {
    return $("<div>").text(text == null ? "" : String(text)).html();
  }

  function flattenArgs(args) {
    return _.flatten(Array.isArray(args) ? args : []);
  }

  function formatTaskCommand(task) {
    var cmd = (task && (task.cmd || task["cmd"] || task.command)) || "unknown";
    var args = flattenArgs(task && (task.args || task["args"]));
    return {
      key: cmd,
      name: commandNames[cmd] || cmd,
      line: [cmd].concat(args).join(" ")
    };
  }

  function formatTaskTime(task, isRunning) {
    var time = isRunning ? (task.started_at || task["started_at"]) : (task.created_at || task["created_at"]);
    if (!time) return "";
    return isRunning ? "開始: " + time : "追加: " + time;
  }

  function renderTask(task, isPending) {
    var info = formatTaskCommand(task);
    var statusText = isPending ? "待機中" : "実行中";
    var timeText = formatTaskTime(task, !isPending);
    var meta = [statusText];
    if (timeText) {
      meta.push(timeText);
    }

    return "" +
      '<li class="queue-task ' + (isPending ? "queue-task--pending" : "queue-task--running") + '"' +
        (isPending ? ' draggable="true"' : "") +
        ' data-task-id="' + escapeHtml(task.id || task["id"] || "") + '">' +
        '<span class="queue-task__handle glyphicon ' + (isPending ? "glyphicon-sort" : "glyphicon-play-circle") + '"></span>' +
        '<div class="queue-task__body">' +
          '<div class="queue-task__title">' + escapeHtml(info.name) + "</div>" +
          '<div class="queue-task__meta">' + escapeHtml(info.line) + "</div>" +
          '<div class="queue-task__meta">' + escapeHtml(meta.join(" / ")) + "</div>" +
        "</div>" +
        (isPending ? (
          '<div class="queue-task__actions">' +
            '<button type="button" class="btn btn-default btn-xs queue-task__move" data-direction="up" title="上へ">' +
              '<span class="glyphicon glyphicon-chevron-up"></span>' +
            "</button>" +
            '<button type="button" class="btn btn-default btn-xs queue-task__move" data-direction="down" title="下へ">' +
              '<span class="glyphicon glyphicon-chevron-down"></span>' +
            "</button>" +
            '<button type="button" class="btn btn-danger btn-xs queue-task__remove" title="削除">' +
              '<span class="glyphicon glyphicon-trash"></span>' +
            "</button>" +
          "</div>"
        ) : "") +
      "</li>";
  }

  function renderTaskSection(title, tasks, isPending, emptyText) {
    var html = '<section class="queue-manager__section">';
    html += '<h4 class="queue-manager__section-title">' + escapeHtml(title) + "</h4>";
    if (!tasks || tasks.length === 0) {
      html += '<div class="queue-manager__empty">' + escapeHtml(emptyText) + "</div>";
    }
    else {
      html += '<ol class="queue-task-list">';
      $.each(tasks, function(_, task) {
        html += renderTask(task, isPending);
      });
      html += "</ol>";
    }
    html += "</section>";
    return html;
  }

  function ensureQueueModal() {
    var $modal = $("#" + queueModalId);
    if ($modal.length > 0) {
      return $modal;
    }

    $modal = $(
      '<div id="' + queueModalId + '" class="modal fade" tabindex="-1" role="dialog" aria-hidden="true">' +
        '<div class="modal-dialog">' +
          '<div class="modal-content">' +
            '<div class="modal-header">' +
              '<button type="button" class="close" data-dismiss="modal" aria-label="Close">' +
                '<span aria-hidden="true">&times;</span>' +
              "</button>" +
              '<h4 class="modal-title">キュー一覧</h4>' +
            "</div>" +
            '<div class="modal-body queue-manager__content"></div>' +
            '<div class="modal-footer">' +
              '<button type="button" class="btn btn-default queue-manager__reload">再読み込み</button>' +
              '<button type="button" class="btn btn-primary" data-dismiss="modal">閉じる</button>' +
            "</div>" +
          "</div>" +
        "</div>" +
      "</div>"
    );

    $("body").append($modal);
    return $modal;
  }

  function renderQueueModal(data) {
    var $modal = ensureQueueModal();
    var running = data && data.running ? data.running : [];
    var pending = data && data.pending ? data.pending : [];
    var html = "";

    html += '<p class="queue-manager__hint">待機中の処理はドラッグ、上下ボタン、削除ボタンで操作できます。</p>';
    html += renderTaskSection("実行中", running, false, "現在実行中の処理はありません");
    html += renderTaskSection("待機中", pending, true, "キューに積まれている待機中の処理はありません");

    $modal.find(".queue-manager__content").html(html);
    return $modal;
  }

  function isQueueModalOpen() {
    var $modal = $("#" + queueModalId);
    return $modal.length > 0 && $modal.hasClass("in");
  }

  function loadQueueModal() {
    return $.get("/api/get_pending_tasks")
      .done(function(data) {
        renderQueueModal(data);
      })
      .fail(function(xhr) {
        var message = (xhr.responseJSON && xhr.responseJSON.error) || "キューの読み込みに失敗しました";
        alert(message);
      });
  }

  function openQueueModal() {
    var $modal = ensureQueueModal();
    loadQueueModal().done(function() {
      $modal.modal("show");
    });
  }

  function refreshQueueModal() {
    if (!isQueueModalOpen()) return;
    loadQueueModal();
  }

  var refreshQueueModalThrottled = _.throttle(refreshQueueModal, 300);

  function syncPendingOrder() {
    var $modal = ensureQueueModal();
    var taskIds = [];
    $modal.find(".queue-task--pending").each(function() {
      taskIds.push(String($(this).data("taskId")));
    });
    if (taskIds.length === 0) {
      return $.Deferred().resolve().promise();
    }
    return $.post("/api/reorder_pending_tasks", { task_ids: taskIds })
      .fail(function(xhr) {
        var message = (xhr.responseJSON && xhr.responseJSON.error) || "キューの並べ替えに失敗しました";
        alert(message);
        refreshQueueModal();
      });
  }

  function removePendingTask(taskId) {
    return $.post("/api/remove_pending_task", { task_id: taskId })
      .done(function() {
        refreshQueueModal();
      })
      .fail(function(xhr) {
        var message = (xhr.responseJSON && xhr.responseJSON.error) || "キューから削除できませんでした";
        alert(message);
        refreshQueueModal();
      });
  }

  notification.on("notification.queue", function(sizes) {
    setQueueSizesText(sizes);
    refreshQueueModalThrottled();
  });

  notification.on("queue.pending_running_tasks", function(tasks) {
    if (!tasks || tasks.length === 0) return;
    var taskList = tasks.map(function(t) {
      return formatTaskCommand(t).line;
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

  $queue.on("click", function(e) {
    e.preventDefault();
    openQueueModal();
  });

  $queue.on("keydown", function(e) {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      openQueueModal();
    }
  });

  $(document).on("click", "#" + queueModalId + " .queue-manager__reload", function() {
    loadQueueModal();
  });

  $(document).on("click", "#" + queueModalId + " .queue-task__move", function(e) {
    e.preventDefault();
    var $task = $(this).closest(".queue-task--pending");
    var direction = $(this).data("direction");
    if (direction === "up") {
      var $prev = $task.prev(".queue-task--pending");
      if ($prev.length > 0) {
        $prev.before($task);
        syncPendingOrder();
      }
    }
    else if (direction === "down") {
      var $next = $task.next(".queue-task--pending");
      if ($next.length > 0) {
        $next.after($task);
        syncPendingOrder();
      }
    }
  });

  $(document).on("click", "#" + queueModalId + " .queue-task__remove", function(e) {
    e.preventDefault();
    var taskId = String($(this).closest(".queue-task--pending").data("taskId"));
    if (confirm("この処理をキューから削除しますか？")) {
      removePendingTask(taskId);
    }
  });

  $(document).on("dragstart", "#" + queueModalId + " .queue-task--pending", function(e) {
    draggingTaskId = String($(this).data("taskId"));
    $(this).addClass("dragging");
    e.originalEvent.dataTransfer.effectAllowed = "move";
    e.originalEvent.dataTransfer.setData("text/plain", draggingTaskId);
  });

  $(document).on("dragend", "#" + queueModalId + " .queue-task--pending", function() {
    draggingTaskId = null;
    $("#" + queueModalId + " .queue-task").removeClass("dragging dragover");
  });

  $(document).on("dragover", "#" + queueModalId + " .queue-task--pending", function(e) {
    e.preventDefault();
    $("#" + queueModalId + " .queue-task--pending").removeClass("dragover");
    $(this).addClass("dragover");
    e.originalEvent.dataTransfer.dropEffect = "move";
  });

  $(document).on("dragleave", "#" + queueModalId + " .queue-task--pending", function() {
    $(this).removeClass("dragover");
  });

  $(document).on("drop", "#" + queueModalId + " .queue-task--pending", function(e) {
    e.preventDefault();
    var sourceTaskId = draggingTaskId || e.originalEvent.dataTransfer.getData("text/plain");
    var $target = $(this);
    var $list = $target.closest(".queue-task-list");
    var $source = $list.find('.queue-task--pending[data-task-id="' + sourceTaskId + '"]');
    if ($source.length === 0 || $source[0] === $target[0]) {
      $target.removeClass("dragover");
      return;
    }

    var rect = this.getBoundingClientRect();
    var insertBefore = (e.originalEvent.clientY - rect.top) < (rect.height / 2);
    if (insertBefore) {
      $target.before($source);
    }
    else {
      $target.after($source);
    }
    $target.removeClass("dragover");
    syncPendingOrder();
  });
});
