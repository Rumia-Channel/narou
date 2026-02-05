/* -*- coding: utf-8 -*-
 *
 * Copyright 2013 whiteleaf. All rights reserved.
 */

/*
 * 全ページ共通のUI関係のコード
 */
$(document).ready(function() {
  "use strict";

  /*
   * タッチデバイス検出とクラス付与
   */
  if ("ontouchstart" in window) {
    $("body").addClass("touch-device");

    // Global double tap detection and click simulation
    var lastTap = 0;
    var lastTarget = null;
    var doubleTapTimeout;
    var DOUBLE_TAP_DELAY = 300; // milliseconds

    $(document).on('touchend', function(e) {
      var currentTime = new Date().getTime();
      var tapLength = currentTime - lastTap;

      // Check if it's a double tap on the same or very similar target
      // (Using closest to allow for slight movement between taps, but within a common interactive element)
      if (lastTarget && $(lastTarget).closest('a, button, [role="button"], tr, li, .form-control').is($(e.target).closest('a, button, [role="button"], tr, li, .form-control')) && tapLength < DOUBLE_TAP_DELAY && tapLength > 0) {
        // Double tap detected
        clearTimeout(doubleTapTimeout);
        e.preventDefault(); // Prevent default browser double-tap behavior (e.g., zooming)
        e.stopPropagation(); // Stop propagation of the touchend

        // Trigger a synthetic click event on the final target
        $(e.target).trigger('click');

        // Reset for next tap sequence
        lastTap = 0;
        lastTarget = null;
      } else {
        lastTap = currentTime;
        lastTarget = e.target;
        // Set a timeout to clear lastTap/lastTarget if no second tap occurs
        doubleTapTimeout = setTimeout(function() {
          lastTap = 0;
          lastTarget = null;
        }, DOUBLE_TAP_DELAY);
      }
    });
  }

  /*
   * bootboxjs 初期設定
   */
  bootbox.setDefaults({
    locale: "ja",
    backdrop: "static",
  });

  /*
   * ページ内リンクをスクロールで移動するための初期化
   * (jquery.moveto.js)
   */
  $.moveTo();

  /*
   * 自然に消えるフラッシュメッセージ
   */
  Narou.Flash.setEvents(".fadeout-alert");

  /*************************************************************************
   * Webサーバの方から入力を求められた時にモーダルを表示して返事を返す
   *************************************************************************/
  (function() {
    var notification = Narou.Notification.instance();
    var boxes = {};

    // モーダル生存確認への応答
    var pong = function(id) {
      var hash = {};
      hash["pong.modal." + id] = true
      notification.send(hash);
    };

    // ユーザの選択をサーバに通知する
    var answer = function(id, result) {
      var hash = {};
      hash["answer.modal." + id] = { result: result };
      notification.send(hash);
    };

    notification.on("ping.modal", function(json) {
      if (boxes[json.id]) pong(json.id);
    });

    // キャンセル、OK を確認する confirm モーダル表示
    notification.on("modal.confirm", function(json) {
      var id = json.id;
      boxes[id] = bootbox.confirm(json.message.replace(/\n/g, "<br>"), function(result) {
        answer(id, result);
      });
    });

    // 選択肢を表示する choose モーダル表示
    notification.on("modal.choose", function(json) {
      var id = json.id;
      var message = "<div>" + json.message.replace(/\n/g, "<br>") + "</div>";
      $.each(json.choices, function(key, val) {
        var label_id = "choice-" + key;
        message += "<div class=radio><label for='" + label_id + "'>" +
          "<input type=radio name=choices id='" + label_id + "' value='" + key + "'>" + val +
          "</label></div>";
      });
      boxes[id] = bootbox.dialog({
        title: json.title,
        message: message,
        closeButton: false,
        buttons: {
          main: {
            label: "決定",
            className: "btn-primary",
            callback: function() {
              var result = $("input[name='choices']:checked").val();
              answer(id, result);
            }
          }
        }
      });
    });

    notification.on("hide.modal", function(json) {
      var box = boxes[json.id];
      if (box) {
        box.modal("hide");
        delete boxes[json.id];
      }
    });

    return;
  })();
});

