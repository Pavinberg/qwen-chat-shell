;;; qwen-chat-shell.el --- Qwen-chat shell + buffer insert commands  -*- lexical-binding: t -*-

;; Copyright (C) 2024 Pavinberg

;; Author: Pavinberg <pavin0702@gmail.com>
;; URL: https://github.com/Pavinberg/qwen-chat-shell
;; Version: 0.0.2
;; Package-Requires: ((emacs "27.1") (shell-maker "0.50.1"))

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `qwen-chat-shell' is a Qwen (https://github.com/QwenLM/Qwen) chat shell
;; that integrates Qwen LLM into Emacs.
;; This package is inspired by chatgpt-shell (https://github.com/xenodium/chatgpt-shell).
;;
;; You must set `qwen-chat-shell-dashscope-key' to your key before using.
;;
;; Run `qwen-chat-shell' to get a Qwen-chat shell.
;;

;;; Code:

(require 'cl-lib)
(require 'dired)
(require 'esh-mode)
(require 'eshell)
(require 'find-func)
(require 'flymake)
(require 'ielm)
(require 'shell-maker)
(require 'ob)
(require 'em-prompt)

(defcustom qwen-chat-shell-dashscope-key nil
  "Dashscope key as a string or a function that loads and returns it."
  :type '(choice (function :tag "Function")
                 (string :tag "String"))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-additional-curl-options nil
  "Additional options for `curl' command."
  :type '(repeat (string :tag "String"))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-auth-header
  (lambda ()
    (format "Authorization: Bearer %s" (qwen-chat-shell-dashscope-key)))
  "Function to generate the request's `Authorization' header string."
  :type '(function :tag "Function")
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-request-timeout 120
  "How long to wait for a request to time out in seconds."
  :type 'integer
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-describe-code
  "请问这段代码在做什么："
  "Prompt header of `describe-code`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-eshell-summarize-last-command-output
  "请将如下命令的输出进行总结："
  "Prompt header of `eshell-summarize-last-command-output`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-whats-wrong-with-last-command
  "这个命令有什么问题？"
  "Prompt header of `whats-wrong-with-last-command`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-generate-unit-test
  "请为如下代码编写单元测试："
  "Prompt header of `generate-unit-test`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-refactor-code
  "请帮我重构以下代码。请用中文回复，解释重构的理由，提供重构后的代码，以及重构前后版本的差异。\
在重构过程中，请忽略代码中的注释和字符串。如果重构后代码保持不变，请回复“无需重构”。"
  "Prompt header of `refactor-code`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-write-git-commit
  "请帮我为如下 commit 编写一个 git commit 信息："
  "Prompt header of `git-commit`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-translate-to-english
  "请帮我把如下内容翻译成英文："
  "Prompt header of `translate-to-english`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-translate-to-chinese
  "请帮我把如下内容翻译成中文："
  "Prompt header of `translate-to-chinese`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-header-proofread-region
  "请帮我校对这段英文用法是否正确："
  "Promt header of `proofread-region`."
  :type 'string
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-default-prompts
  '(qwen-chat-shell-prompt-header-describe-code
    qwen-chat-shell-prompt-header-eshell-summarize-last-command-output
    qwen-chat-shell-prompt-header-whats-wrong-with-last-command
    qwen-chat-shell-prompt-header-generate-unit-test
    qwen-chat-shell-prompt-header-refactor-code)
  "List of default prompts to choose from."
  :type '(repeat string)
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-prompt-query-response-style 'other-buffer
  "Determines the prompt style when invoking from other buffers.

`'inline' inserts responses into current buffer.
`'other-buffer' inserts responses into a transient buffer.
`'shell' inserts responses and focuses the shell

Note: in all cases responses are written to the shell to keep context."
  :type '(choice (const :tag "Inline" inline)
                 (const :tag "Other Buffer" other-buffer)
                 (const :tag "Shell" shell))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-after-command-functions nil
  "Abnormal hook (i.e. with parameters) invoked after each command.

This is useful if you'd like to automatically handle or suggest things
post execution.

For example:

\(add-hook `qwen-chat-shell-after-command-functions'
   (lambda (command output)
     (message \"Command: %s\" command)
     (message \"Output: %s\" output)))"
  :type 'hook
  :group 'shell-maker)

(defvaralias 'qwen-chat-shell-display-function 'shell-maker-display-function)

(defvaralias 'qwen-chat-shell-read-string-function 'shell-maker-read-string-function)

(defvaralias 'qwen-chat-shell-logging 'shell-maker-logging)

(defvaralias 'qwen-chat-shell-root-path 'shell-maker-root-path)

(defalias 'qwen-chat-shell-save-session-transcript #'shell-maker-save-session-transcript)

(defvar qwen-chat-shell--prompt-history nil)

(defcustom qwen-chat-shell-language-mapping '(("elisp" . "emacs-lisp")
                                            ("objective-c" . "objc")
                                            ("objectivec" . "objc")
                                            ("cpp" . "c++"))
  "Maps external language names to Emacs names.
Use only lower-case names.

For example:
                  lowercase      Emacs mode (without -mode)
Objective-C -> (\"objective-c\" . \"objc\")"
  :type '(alist :key-type (string :tag "Language Name/Alias")
                :value-type (string :tag "Mode Name (without -mode)"))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-babel-headers '(("dot" . ((:file . "<temp-file>.png")))
                                           ("plantuml" . ((:file . "<temp-file>.png")))
                                           ("ditaa" . ((:file . "<temp-file>.png")))
                                           ("objc" . ((:results . "output")))
                                           ("python" . ((:python . "python3") (:results . "output")))
                                           ("swiftui" . ((:results . "file")))
                                           ("c++" . ((:results . "raw") (:results . "output")))
                                           ("c" . ((:results . "raw") (:results . "output"))))
  "Additional headers to make babel blocks work.

Entries are of the form (language . headers).  Headers should
conform to the types of `org-babel-default-header-args', which
see.

Please submit contributions so more things work out of the box."
  :type '(alist :key-type (string :tag "Language")
                :value-type (alist :key-type (restricted-sexp :match-alternatives (keywordp) :tag "Argument Name")
                                   :value-type (string :tag "Value")))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-source-block-actions
  nil
  "Block actions for known languages.

Can be used compile or run source block at point."
  :type '(alist :key-type (string :tag "Language")
                :value-type (alist :key-type (string :tag "Confirmation Prompt:")
                                   :value-type (function :tag "Action:")))
                ;; :value-type (list (cons (const 'primary-action-confirmation) (string :tag "Confirmation Prompt:"))
                ;;                   (cons (const 'primary-action) (function :tag "Action:"))))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-available-models
  '("qwen2-0.5b-instruct"
    "qwen2-1.5b-instruct"
    "qwen2-7b-instruct"
    "qwen2-72b-instruct"
    "qwen2-57b-a14b-instruct"
    "qwen1.5-0.5b-chat"
    "qwen1.5-1.8b-chat"
    "qwen1.5-7b-chat"
    "qwen1.5-14b-chat"
    "qwen1.5-32b-chat"
    "qwen1.5-72b-chat"
    "qwen1.5-110b-chat"
    "qwen-1.8b-chat"
    "qwen-7b-chat"
    "qwen-14b-chat"
    "qwen-72b-chat"
    "codeqwen1.5-7b-chat"
    "qwen-turbo"
    "qwen-plus"
    "qwen-max"
    "qwen-max-0428"
    "qwen-max-longcontext"
    "qwen-long"
    "qwen-1.8b-longcontext-chat")
  "The list of Qwen models to choose from.

Currently we use OpenAI compatible API for simplicity, documented at
https://help.aliyun.com/zh/dashscope/developer-reference/openai-file-interface

The list of models supported by /v1/chat/completions endpoint is
documented at
https://help.aliyun.com/zh/dashscope/developer-reference/\
compatibility-of-openai-with-dashscope/

The list of all models is at
https://help.aliyun.com/zh/dashscope/developer-reference/model-square/"
  :type '(repeat string)
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-current-model 1
  "The active Qwen model index.

See `qwen-chat-shell-available-models' for available models.
Switch model using `qwen-chat-shell-switch-model'.

The list of models supported by /v1/chat/completions endpoint is documented at
https://help.aliyun.com/zh/dashscope/developer-reference/compatibility-of-openai-with-dashscope/"
  :type '(choice (string :tag "String")
                 (integer :tag "Integer")
                 (const :tag "Nil" nil))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-model-temperature nil
  "What sampling temperature to use, between [0, 2), or nil.

Higher values like 0.8 will make the output more random, while
lower values like 0.2 will make it more focused and
deterministic.  Value of nil will not pass this configuration to
the model.

See
https://help.aliyun.com/zh/dashscope/developer-reference/\
compatibility-of-openai-with-dashscope/#d553cbbee6mxk for details."
  :type '(choice (float :tag "Float")
                 (const :tag "Nil" nil))
  :group 'qwen-chat-shell)

(defun qwen-chat-shell--append-system-info (text)
  "Append system info to TEXT."
  (cl-labels ((qwen-chat-shell--get-system-info-command
               ()
               (cond ((eq system-type 'darwin) "sw_vers")
                     ((or (eq system-type 'gnu/linux)
                          (eq system-type 'gnu/kfreebsd)) "uname -a")
                     ((eq system-type 'windows-nt) "ver")
                     (t (format "%s" system-type)))))
    (let ((system-info (string-trim
                        (shell-command-to-string
                         (qwen-chat-shell--get-system-info-command)))))
      (concat text
              "\n# System info\n"
              "\n## OS details\n"
              system-info
              "\n## Editor\n"
              (emacs-version)))))

(defcustom qwen-chat-shell-system-prompts
  `(("Brief" . "请尽可能简洁且提供有用信息，在回答我的问题时使用摘要形式。")
    ("General" . "请使用 Markdown 格式来回复。")
    ("Programming" . ,(qwen-chat-shell--append-system-info
                       "用户是一位时间非常有限的程序员。你要珍惜他们的时间，不要重复显而易见的事情，例如重复他们的问题。在回复中尽可能简洁。不要为犯错道歉，因为这会浪费他们的时间。请使用 Markdown 格式来回复，在展示代码片段时要在 Markdown 的代码块中加上语言标签。不要解释代码片段。每当你为用户输出新的代码时，只展示代码的差别，而不需要展示完整的代码片段。"))
    ("Positive Programming" . ,(qwen-chat-shell--append-system-info
                                "你的目标是帮助用户成为一名出色的计算机程序员。你保持积极和鼓励的态度，你喜欢看到他们学习成长。不要重复显而易见的事情，例如重复他们的问题。你的回答尽可能简洁。你总是引导用户更深入地理解，帮助他们看到底层原理。不要为犯错而道歉，因为这会浪费他们的时间。请使用 Markdown 格式来回复，在展示代码片段时要在 Markdown 的代码块中加上语言标签。不用解释代码片段。每当你为用户输出更新的代码时，只展示差别，而不是完整的代码片段。")))
  "List of system prompts to choose from.

If prompt is a cons, its car will be used as a title to display."
  :type '(alist :key-type (string :tag "Title")
                :value-type (string :tag "Prompt value"))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-system-prompt 0 ;; Concise
  "The system prompt `qwen-chat-shell-system-prompts' index.

Or nil if none."
  :type '(choice (string :tag "String")
                 (integer :tag "Integer")
                 (const :tag "No Prompt" nil))
  :group 'qwen-chat-shell)

(defvar-local qwen-chat-shell--is-primary-p nil)
(defvar-local qwen-chat-shell--ring-index nil)

(defun qwen-chat-shell-current-model ()
  "Return current active model."
  (cond ((stringp qwen-chat-shell-current-model)
         qwen-chat-shell-current-model)
        ((integerp qwen-chat-shell-current-model)
         (nth qwen-chat-shell-current-model
              qwen-chat-shell-available-models))
        (t
         nil)))

(defun qwen-chat-shell-system-prompt ()
  "Return active system prompt."
  (cond ((stringp qwen-chat-shell-system-prompt)
         qwen-chat-shell-system-prompt)
        ((integerp qwen-chat-shell-system-prompt)
         (let ((prompt (nth qwen-chat-shell-system-prompt
                            qwen-chat-shell-system-prompts)))
           (if (consp prompt)
               (cdr prompt)
             prompt)))
        (t
         nil)))

(defun qwen-chat-shell-duplicate-map-keys (map)
  "Return duplicate keys in MAP."
  (let ((keys (map-keys map))
        (seen '())
        (duplicates '()))
    (dolist (key keys)
      (if (member key seen)
          (push key duplicates)
        (push key seen)))
    duplicates))

(defun qwen-chat-shell-switch-system-prompt ()
  "Switch system prompt from `qwen-chat-shell-system-prompts'."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (when-let ((duplicates (qwen-chat-shell-duplicate-map-keys qwen-chat-shell-system-prompts)))
    (user-error "Duplicate prompt names found %s. Please remove" duplicates))
  (let* ((choices (append (list "None")
                          (map-keys qwen-chat-shell-system-prompts)))
         (choice (completing-read "System prompt: " choices))
         (choice-pos (seq-position choices choice)))
    (if (or (string-equal choice "None")
            (string-empty-p (string-trim choice))
            (not choice-pos))
        (setq-local qwen-chat-shell-system-prompt nil)
      (setq-local qwen-chat-shell-system-prompt
                  ;; -1 to disregard None
                  (1- (seq-position choices choice)))))
  (qwen-chat-shell--update-prompt t)
  (qwen-chat-shell-interrupt nil))

(defun qwen-chat-shell-switch-model ()
  "Switch model from `qwen-chat-shell-available-models'."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (setq-local qwen-chat-shell-current-model
              (completing-read "Model: "
                               (if (> (length qwen-chat-shell-available-models) 1)
                                   (seq-remove
                                    (lambda (item)
                                      (string-equal item (qwen-chat-shell-current-model)))
                                    qwen-chat-shell-available-models)
                                 qwen-chat-shell-available-models) nil t))
  (qwen-chat-shell--update-prompt t)
  (qwen-chat-shell-interrupt nil))

(defcustom qwen-chat-shell-streaming t
  "Whether or not to stream model responses (show chunks as they arrive)."
  :type 'boolean
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-highlight-blocks t
  "Whether or not to highlight source blocks."
  :type 'boolean
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-transmitted-context-length
  #'qwen-chat-shell--approximate-context-length
  "Controls the amount of context provided to LLM.

This context needs to be transmitted to the API on every request.
LLM reads the provided context on every request, which will
consume more and more prompt tokens as your conversation grows.
Models do have a maximum token limit, however.

A value of nil will send full chat history (the full contents of
the comint buffer), to LLM.

A value of 0 will not provide any context.  This is the cheapest
option, but LLM can't look back on your conversation.

A value of 1 will send only the latest prompt-completion pair as
context.

A Value > 1 will send that amount of prompt-completion pairs to LLM.

A function `(lambda (tokens-per-message tokens-per-name messages))'
returning length.  Can use custom logic to enable a shifting context
window."
  :type '(choice (integer :tag "Integer")
                 (const :tag "Not set" nil)
                 (function :tag "Function"))
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-api-url-base "https://dashscope.aliyuncs.com/compatible-mode"
  "Qwen dashscope API's base URL.

`qwen-chat-shell--api-url' =
   `qwen-chat-shell--api-url-base' + `qwen-chat-shell--api-url-path'

If you use Qwen through a proxy service, change the URL base."
  :type 'string
  :safe #'stringp
  :group 'qwen-chat-shell)

(defcustom qwen-chat-shell-api-url-path "/v1/chat/completions"
  "Qwen dashscope API's URL path.

`qwen-chat-shell--api-url' =
   `qwen-chat-shell--api-url-base' + `qwen-chat-shell--api-url-path'"
  :type 'string
  :safe #'stringp
  :group 'qwen-chat-shell)

(defun qwen-chat-shell-welcome-message (config)
  "Return a welcome message to be printed using CONFIG."
  (format
   "Welcome to %s shell! \n\n  Type %s and press %s for details\n\n"
   (propertize (shell-maker-config-name config)
               'font-lock-face 'font-lock-comment-face)
   (propertize "help" 'font-lock-face 'italic)
   (shell-maker--propertize-key-binding "-shell-submit" config)))

(defcustom qwen-chat-shell-welcome-function #'qwen-chat-shell-welcome-message
  "Function returning welcome message or nil for no message.

See `shell-maker-welcome-message' as an example."
  :type 'function
  :group 'qwen-chat-shell)

(defvar qwen-chat-shell--config
  (make-shell-maker-config
   :name "Qwen-chat"
   :validate-command
   (lambda (_command)
     (unless qwen-chat-shell-dashscope-key
       "Variable `qwen-chat-shell-dashscope-key' needs to be set to your API-key.

Try M-x set-variable qwen-chat-shell-dashscope-key

or

(setq qwen-chat-shell-dashscope-key \"my-key\")

To create the API-key: https://help.aliyun.com/zh/dashscope/developer-reference/activate-dashscope-and-create-an-api-key"))
   :execute-command
   (lambda (_command history callback error-callback)
     (shell-maker-async-shell-command
      (qwen-chat-shell--make-curl-request-command-list
       (qwen-chat-shell--make-payload history))
      qwen-chat-shell-streaming
      #'qwen-chat-shell--extract-dashscope-response
      callback
      error-callback))
   :on-command-finished
   (lambda (command output)
     (qwen-chat-shell--put-source-block-overlays)
     (run-hook-with-args 'qwen-chat-shell-after-command-functions
                         command output))
   :redact-log-output
   (lambda (output)
     (if (qwen-chat-shell-dashscope-key)
         (replace-regexp-in-string (regexp-quote (qwen-chat-shell-dashscope-key))
                                   "SK-REDACTED-DASHSCOPE-KEY"
                                   output)
       output))))

(defalias 'qwen-chat-shell-clear-buffer #'comint-clear-buffer)

(defalias 'qwen-chat-shell-explain-code #'qwen-chat-shell-describe-code)

;; Aliasing enables editing as text in babel.
(defalias 'qwen-chat-shell-mode #'text-mode)

(defvar qwen-chat-shell-mode-map)
(shell-maker-define-major-mode qwen-chat-shell--config) ; then qwen-chat-shell-mode-map is defined

;;;###autoload
(defun qwen-chat-shell (&optional new-session)
  "Start a Qwen shell interactive command.

With NEW-SESSION, start a new session."
  (interactive "P")
  (when (boundp 'qwen-chat-shell-history-path)
    (error "The qwen-chat-shell-history-path no longer exists.
Please migrate to qwen-chat-shell-root-path and then (makunbound 'qwen-chat-shell-history-path)"))
  (qwen-chat-shell-start nil new-session))

(defun qwen-chat-shell-start (&optional no-focus new-session)
  "Start a `qwen-chat-shell' programmatically.

Set NO-FOCUS to start in background.

Set NEW-SESSION to start a separate new session."
  (let* ((qwen-chat-shell--config
          (let ((config (copy-sequence qwen-chat-shell--config)))
            (setf (shell-maker-config-prompt config)
                  (car (qwen-chat-shell--prompt-pair)))
            (setf (shell-maker-config-prompt-regexp config)
                  (cdr (qwen-chat-shell--prompt-pair)))
            config))
         (shell-buffer
          (shell-maker-start qwen-chat-shell--config
                             no-focus
                             qwen-chat-shell-welcome-function
                             new-session
                             (if (qwen-chat-shell--primary-buffer)
                                 (buffer-name (qwen-chat-shell--primary-buffer))
                               (qwen-chat-shell--make-buffer-name)))))
    (unless (qwen-chat-shell--primary-buffer)
      (qwen-chat-shell--set-primary-buffer shell-buffer))
    (let ((model qwen-chat-shell-current-model)
          (system-prompt qwen-chat-shell-system-prompt))
      (with-current-buffer shell-buffer
        (setq-local qwen-chat-shell-current-model model)
        (setq-local qwen-chat-shell-system-prompt system-prompt)
        (qwen-chat-shell--update-prompt t)
        (qwen-chat-shell--add-menus)))
    ;; Disabling advice for now. It gets in the way.
     (define-key qwen-chat-shell-mode-map (kbd "C-M-h")
                 #'qwen-chat-shell-mark-at-point-dwim)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-c")
                 #'qwen-chat-shell-ctrl-c-ctrl-c)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-v")
                 #'qwen-chat-shell-switch-model)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-s")
                 #'qwen-chat-shell-switch-system-prompt)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-p")
                 #'qwen-chat-shell-previous-item)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-n")
                 #'qwen-chat-shell-next-item)
     (define-key qwen-chat-shell-mode-map (kbd "C-c C-e")
                 #'qwen-chat-shell-prompt-compose)
    shell-buffer))

(defun qwen-chat-shell--shrink-model-name (model-name)
  "Shrink MODEL-NAME.  For example, qwen-14b-chat -> 14b."
  (string-remove-suffix
   "-instruct"
   (string-remove-suffix
    "-chat"
    (string-remove-prefix
     "qwen-" (string-trim model-name)))))

(defun qwen-chat-shell--shrink-system-prompt (prompt)
  "Shrink PROMPT."
  (if (consp prompt)
      (qwen-chat-shell--shrink-system-prompt (car prompt))
    (if (> (length (string-trim prompt)) 15)
        (format "%s..."
                (substring (string-trim prompt) 0 12))
      (string-trim prompt))))

(defun qwen-chat-shell--shell-info ()
  "Generate shell info for display."
  (concat
   (qwen-chat-shell--shrink-model-name
    (qwen-chat-shell-current-model))
   (cond ((and (integerp qwen-chat-shell-system-prompt)
               (nth qwen-chat-shell-system-prompt
                    qwen-chat-shell-system-prompts))
          (concat "/" (qwen-chat-shell--shrink-system-prompt (nth qwen-chat-shell-system-prompt
                                                                qwen-chat-shell-system-prompts))))
         ((stringp qwen-chat-shell-system-prompt)
          (concat "/" (qwen-chat-shell--shrink-system-prompt qwen-chat-shell-system-prompt)))
         (t
          ""))))

(defun qwen-chat-shell--prompt-pair ()
  "Return a pair with prompt and prompt-regexp."
  (cons
   (format "Qwen(%s)> " (qwen-chat-shell--shell-info))
   (rx (seq bol "Qwen" (one-or-more (not (any "\n"))) ">" (or space "\n")))))

(defun qwen-chat-shell--shell-buffers ()
  "Return a list of all shell buffers."
  (seq-filter
   (lambda (buffer)
     (eq (buffer-local-value 'major-mode buffer)
         'qwen-chat-shell-mode))
   (buffer-list)))

(defun qwen-chat-shell-set-as-primary-shell ()
  "Set as primary shell when there are multiple sessions."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (qwen-chat-shell--set-primary-buffer (current-buffer)))

(defun qwen-chat-shell--set-primary-buffer (primary-shell-buffer)
  "Set PRIMARY-SHELL-BUFFER as primary buffer."
  (mapc (lambda (shell-buffer)
          (with-current-buffer shell-buffer
            (setq qwen-chat-shell--is-primary-p nil)))
        (qwen-chat-shell--shell-buffers))
  (with-current-buffer primary-shell-buffer
    (setq qwen-chat-shell--is-primary-p t)))

(defun qwen-chat-shell--primary-buffer ()
  "Return the primary shell buffer.

This is used for sending a prompt to in the background."
  (let ((primary-shell-buffer (seq-find
                               (lambda (shell-buffer)
                                 (with-current-buffer shell-buffer
                                   qwen-chat-shell--is-primary-p))
                               (qwen-chat-shell--shell-buffers))))
    primary-shell-buffer))

(defun qwen-chat-shell--make-buffer-name ()
  "Generate a buffer name using current shell config info."
  (format "%s %s"
          (shell-maker-buffer-default-name
           (shell-maker-config-name qwen-chat-shell--config))
          (qwen-chat-shell--shell-info)))

(defun qwen-chat-shell--add-menus ()
  "Add LLM chat shell menu items."
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (when-let ((duplicates (qwen-chat-shell-duplicate-map-keys qwen-chat-shell-system-prompts)))
    (user-error "Duplicate prompt names found %s. Please remove.?" duplicates))
  (easy-menu-define qwen-chat-shell-system-prompts-menu (current-local-map) "Qwen"
    `("Qwen"
      ("Models"
       ,@(mapcar (lambda (model)
                   `[,model
                     (lambda ()
                       (interactive)
                       (setq-local qwen-chat-shell-current-model
                                   (seq-position qwen-chat-shell-available-models ,model))
                       (qwen-chat-shell--update-prompt t)
                       (qwen-chat-shell-interrupt nil))])
                 qwen-chat-shell-available-models))
      ("Prompts"
       ,@(mapcar (lambda (prompt)
                   `[,(car prompt)
                     (lambda ()
                       (interactive)
                       (setq-local qwen-chat-shell-system-prompt
                                   (seq-position (map-keys qwen-chat-shell-system-prompts) ,(car prompt)))
                       (qwen-chat-shell--update-prompt t)
                       (qwen-chat-shell-interrupt nil))])
                 qwen-chat-shell-system-prompts)))))

(defun qwen-chat-shell--update-prompt (rename-buffer)
  "Update prompt and prompt regexp from `qwen-chat-shell-available-models'.

Set RENAME-BUFFER to also rename the buffer accordingly."
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (shell-maker-set-prompt
   (car (qwen-chat-shell--prompt-pair))
   (cdr (qwen-chat-shell--prompt-pair)))
  (when rename-buffer
    (shell-maker-set-buffer-name
     (current-buffer)
     (qwen-chat-shell--make-buffer-name))))

(defun qwen-chat-shell--adviced-keyboard-quit (orig-fun &rest args)
  "Advice around `keyboard-quit' interrupting active shell.

Applies ORIG-FUN and ARGS."
  (qwen-chat-shell-interrupt nil)
  (apply orig-fun args))

(defun qwen-chat-shell-interrupt (ignore-item)
  "Interrupt `qwen-chat-shell' from any buffer.

With prefix IGNORE-ITEM, do not mark as failed."
  (interactive "P")
  (with-current-buffer
      (cond
       ((eq major-mode 'qwen-chat-shell-mode)
        (current-buffer))
       (t
        (shell-maker-buffer-name qwen-chat-shell--config)))
    (shell-maker-interrupt ignore-item)))

(defun qwen-chat-shell-ctrl-c-ctrl-c (ignore-item)
  "If point in source block, execute it.  Otherwise interrupt.

With prefix IGNORE-ITEM, do not use interrupted item in context."
  (interactive "P")
  (cond ((qwen-chat-shell-block-action-at-point)
         (qwen-chat-shell-execute-block-action-at-point))
        ((qwen-chat-shell-markdown-block-at-point)
         (user-error "No action available"))
        ((and shell-maker--busy
              (eq (line-number-at-pos (point-max))
                  (line-number-at-pos (point))))
         (shell-maker-interrupt ignore-item))
        (t
         (shell-maker-interrupt ignore-item))))

(defun qwen-chat-shell-mark-at-point-dwim ()
  "Mark source block if at point.  Mark all output otherwise."
  (interactive)
  (if-let ((block (qwen-chat-shell-markdown-block-at-point)))
      (progn
        (set-mark (map-elt block 'end))
        (goto-char (map-elt block 'start)))
    (shell-maker-mark-output)))

(defun qwen-chat-shell-markdown-block-language (text)
  "Get the language label of a Markdown TEXT code block."
  (when (string-match (rx bol "```" (0+ space) (group (+ (not (any "\n"))))) text)
    (match-string 1 text)))

(defun qwen-chat-shell-markdown-block-at-point ()
  "Markdown start/end cons if point at block.  nil otherwise."
  (save-excursion
    (save-restriction
      (when (eq major-mode 'qwen-chat-shell-mode)
        (shell-maker-narrow-to-prompt))
      (let* ((language)
             (language-start)
             (language-end)
             (start (save-excursion
                      (when (re-search-backward "^```" nil t)
                        (setq language (qwen-chat-shell-markdown-block-language (thing-at-point 'line)))
                        (save-excursion
                          (forward-char 3) ; ```
                          (setq language-start (point))
                          (end-of-line)
                          (setq language-end (point)))
                        language-end)))
             (end (save-excursion
                    (when (re-search-forward "^```" nil t)
                      (forward-line 0)
                      (point)))))
        (when (and start end
                   (> (point) start)
                   (< (point) end))
          (list (cons 'language language)
                (cons 'language-start language-start)
                (cons 'language-end language-end)
                (cons 'start start)
                (cons 'end end)))))))

(defun qwen-chat-shell--markdown-headers (&optional avoid-ranges)
  "Extract markdown headers with AVOID-RANGES."
  (let ((headers '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx bol (group (one-or-more "#"))
                  (one-or-more space)
                  (group (one-or-more (not (any "\n")))) eol)
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'start begin
              'end end
              'level (cons (match-beginning 1) (match-end 1))
              'title (cons (match-beginning 2) (match-end 2)))
             headers)))))
    (nreverse headers)))

(defun qwen-chat-shell--markdown-links (&optional avoid-ranges)
  "Extract markdown links with AVOID-RANGES."
  (let ((links '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx (seq "["
                       (group (one-or-more (not (any "]"))))
                       "]"
                       "("
                       (group (one-or-more (not (any ")"))))
                       ")"))
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'start begin
              'end end
              'title (cons (match-beginning 1) (match-end 1))
              'url (cons (match-beginning 2) (match-end 2)))
             links)))))
    (nreverse links)))

(defun qwen-chat-shell--markdown-bolds (&optional avoid-ranges)
  "Extract markdown bolds with AVOID-RANGES."
  (let ((bolds '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx (or (group "**" (group (one-or-more (not (any "\n*")))) "**")
                      (group "__" (group (one-or-more (not (any "\n_")))) "__")))
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'start begin
              'end end
              'text (cons (or (match-beginning 2)
                              (match-beginning 4))
                          (or (match-end 2)
                              (match-end 4))))
             bolds)))))
    (nreverse bolds)))

(defun qwen-chat-shell--markdown-strikethroughs (&optional avoid-ranges)
  "Extract markdown strikethroughs with AVOID-RANGES."
  (let ((strikethroughs '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx "~~" (group (one-or-more (not (any "\n~")))) "~~")
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'start begin
              'end end
              'text (cons (match-beginning 1)
                          (match-end 1)))
             strikethroughs)))))
    (nreverse strikethroughs)))

(defun qwen-chat-shell--markdown-italics (&optional avoid-ranges)
  "Extract markdown italics with AVOID-RANGES."
  (let ((italics '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx (or (group (or bol (one-or-more (any "\n \t")))
                             (group "*")
                             (group (one-or-more (not (any "\n*")))) "*")
                      (group (or bol (one-or-more (any "\n \t")))
                             (group "_")
                             (group (one-or-more (not (any "\n_")))) "_")))
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'start (or (match-beginning 2)
                         (match-beginning 5))
              'end end
              'text (cons (or (match-beginning 3)
                              (match-beginning 6))
                          (or (match-end 3)
                              (match-end 6))))
             italics)))))
    (nreverse italics)))

(defun qwen-chat-shell--markdown-inline-codes (&optional avoid-ranges)
  "Get a list of all inline markdown code in buffer with AVOID-RANGES."
  (let ((codes '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "`\\([^`\n]+\\)`"
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (unless (seq-find (lambda (avoided)
                              (and (>= begin (car avoided))
                                   (<= end (cdr avoided))))
                            avoid-ranges)
            (push
             (list
              'body (cons (match-beginning 1) (match-end 1))) codes)))))
    (nreverse codes)))

(defvar qwen-chat-shell--source-block-regexp
  (rx  bol (zero-or-more whitespace) (group "```") (zero-or-more whitespace) ;; ```
       (group (zero-or-more (or alphanumeric "-" "+"))) ;; language
       (zero-or-more whitespace)
       (one-or-more "\n")
       (group (*? anychar)) ;; body
       (one-or-more "\n")
       (group "```") (or "\n" eol)))

(defun qwen-chat-shell-next-source-block ()
  "Move point to previous source block."
  (interactive)
  (when-let
      ((next-block
        (save-excursion
          (when-let ((current (qwen-chat-shell-markdown-block-at-point)))
            (goto-char (map-elt current 'end))
            (end-of-line))
          (when (re-search-forward qwen-chat-shell--source-block-regexp nil t)
            (qwen-chat-shell--match-source-block)))))
    (goto-char (car (map-elt next-block 'body)))))

(defun qwen-chat-shell-previous-item ()
  "Go to previous item.

Could be a prompt or a source block."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (let ((prompt-pos (save-excursion
                      (when (comint-next-prompt (- 1))
                        (point))))
        (block-pos (save-excursion
                     (when (qwen-chat-shell-previous-source-block)
                       (point)))))
    (cond ((and block-pos prompt-pos)
           (goto-char (max prompt-pos
                           block-pos)))
          (block-pos
           (goto-char block-pos))
          (prompt-pos
           (goto-char prompt-pos)))))

(defun qwen-chat-shell-next-item ()
  "Go to next item.

Could be a prompt or a source block."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (let ((prompt-pos (save-excursion
                      (when (comint-next-prompt 1)
                        (point))))
        (block-pos (save-excursion
                     (when (qwen-chat-shell-next-source-block)
                       (point)))))
    (cond ((and block-pos prompt-pos)
           (goto-char (min prompt-pos
                           block-pos)))
          (block-pos
           (goto-char block-pos))
          (prompt-pos
           (goto-char prompt-pos)))))

(defun qwen-chat-shell-previous-source-block ()
  "Move point to previous source block."
  (interactive)
  (when-let
      ((previous-block
        (save-excursion
          (when-let ((current (qwen-chat-shell-markdown-block-at-point)))
            (goto-char (map-elt current 'start))
            (forward-line 0))
          (when (re-search-backward qwen-chat-shell--source-block-regexp nil t)
            (qwen-chat-shell--match-source-block)))))
    (goto-char (car (map-elt previous-block 'body)))))

(defun qwen-chat-shell--match-source-block ()
  "Return a matched source block by the previous search/regexp operation."
  (list
   'start (cons (match-beginning 1)
                (match-end 1))
   'end (cons (match-beginning 4)
              (match-end 4))
   'language (when (and (match-beginning 2)
                        (match-end 2))
               (cons (match-beginning 2)
                     (match-end 2)))
   'body (cons (match-beginning 3) (match-end 3))))

(defun qwen-chat-shell--source-blocks ()
  "Get a list of all source blocks in buffer."
  (let ((markdown-blocks '())
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              qwen-chat-shell--source-block-regexp
              nil t)
        (when-let ((begin (match-beginning 0))
                   (end (match-end 0)))
          (push (qwen-chat-shell--match-source-block)
                markdown-blocks))))
    (nreverse markdown-blocks)))

(defun qwen-chat-shell--minibuffer-prompt ()
  "Construct a prompt for the minibuffer."
  (if (qwen-chat-shell--primary-buffer)
      (concat (buffer-name (qwen-chat-shell--primary-buffer)) "> ")
    (shell-maker-prompt
     qwen-chat-shell--config)))

(defun qwen-chat-shell-prompt ()
  "Make a model request from the minibuffer.

If region is active, append to prompt."
  (interactive)
  (unless qwen-chat-shell--prompt-history
    (setq qwen-chat-shell--prompt-history
          qwen-chat-shell-default-prompts))
  (let ((overlay-blocks (derived-mode-p 'prog-mode))
        (prompt (funcall shell-maker-read-string-function
                         (concat
                          (if (region-active-p)
                              "[appending region] "
                            "")
                          (qwen-chat-shell--minibuffer-prompt))
                         'qwen-chat-shell--prompt-history)))
    (when (string-empty-p (string-trim prompt))
      (user-error "Nothing to send"))
    (when (region-active-p)
      (setq prompt (concat prompt "\n\n"
                           (if overlay-blocks
                               (format "``` %s\n"
                                       (string-remove-suffix "-mode" (format "%s" major-mode)))
                             "")
                           (buffer-substring (region-beginning) (region-end))
                           (if overlay-blocks
                               "\n```"
                             ""))))
    (qwen-chat-shell-send-to-buffer prompt nil)))

(defun qwen-chat-shell-prompt-compose (prefix)
  "Compose and send prompt (kbd \"C-c C-c\") from a dedicated buffer.

With PREFIX, clear existing history (wipe asociated shell history).

Whenever `qwen-chat-shell-prompt-compose' is invoked, appends any active
region (or flymake issue at point) to compose buffer.

The compose buffer always shows the latest interaction, but it's
backed by the shell history.  You can always switch to the shell buffer
to view the history.

Note: There's a fair bit of functionality packed in the compose buffer
and fairly experimental (implementation needs plenty of cleaning up),
but I'm finding it fairly useful.  I need to split it out into a
separate major mode, but I'll list the current functionality in case
folks want to try it out.

Editing: While in edit mode, it offers a couple of magit-like commit
buffer bindings.

 `\\[qwen-chat-shell-ctrl-c-ctrl-c]' to send the buffer query.
 `M-r' search through history.
 `M-p' cycle through previous item in history.
 `M-n' cycle through next item in history.

Read-only: After sending a query, the buffer becomes read-only and
enables additional key bindings.

 `\\[qwen-chat-shell-ctrl-c-ctrl-c]' After sending offers to abort query in-progress.
 `q' Exits the read-only buffer.
 `g' Refresh (re-send the query).  Useful to retry on disconnects.
 `n' Jump to next source block.
 `p' Jump to next previous block.
 `r' Reply to follow-up with additional questions.
 `e' Send \"Show entire snippet\" query (useful to request alternative
 `o' Jump to other buffer (ie. the shell itself).
 `\\[qwen-chat-shell-mark-at-point-dwim]' Mark block at point."
  (interactive "P")
  (unless (qwen-chat-shell--primary-buffer)
    (qwen-chat-shell--set-primary-buffer
     (shell-maker-start qwen-chat-shell--config
                        t
                        qwen-chat-shell-welcome-function
                        t
                        (qwen-chat-shell--make-buffer-name))))
  (let* ((exit-on-submit (eq major-mode 'qwen-chat-shell-mode))
         (buffer-name (concat (qwen-chat-shell--minibuffer-prompt)
                              "compose"))
         (buffer (get-buffer-create buffer-name))
         (region (or (when-let ((region-active (region-active-p))
                                (region (buffer-substring (region-beginning)
                                                          (region-end))))
                       (deactivate-mark)
                       region)
                     (when-let ((diagnostic (flymake-diagnostics (point))))
                       (mapconcat #'flymake-diagnostic-text diagnostic "\n"))))
         (instructions (concat "Type "
                               (propertize "C-c C-c" 'face 'help-key-binding)
                               " to send prompt. "
                               (propertize "C-c C-k" 'face 'help-key-binding)
                               " to cancel and exit. "))
         (erase-buffer (or prefix
                           (not region)
                           ;; view-mode = old query, erase for new one.
                           (with-current-buffer buffer
                             view-mode)))
         (prompt))
    (with-current-buffer buffer
      (visual-line-mode +1)
      (when view-mode
        (view-mode -1))
      (when erase-buffer
        (erase-buffer))
      (when region
        (save-excursion
          (goto-char (point-min))
          (let ((insert-trailing-newlines (not (looking-at-p "\n\n"))))
            (insert "\n\n")
            (insert region)
            (when insert-trailing-newlines
              (insert "\n\n")))))
      (when prefix
        (let ((qwen-chat-shell-prompt-query-response-style 'inline))
          (qwen-chat-shell-send-to-buffer "clear")))
      (make-local-variable 'view-mode-map)
      ;; TODO: Find a better alternative to prevent clash.
      ;; Disable "n"/"p" for region-bindings-mode-map, so it doesn't
      ;; clash with "n"/"p" selection binding.
      (when (boundp 'region-bindings-mode-disable-predicates)
        (add-to-list 'region-bindings-mode-disable-predicates
                     (lambda () buffer-read-only)))
      (define-key view-mode-map (kbd "g")
                  (lambda ()
                    (interactive)
                    (when-let ((prompt (with-current-buffer (qwen-chat-shell--primary-buffer)
                                         (seq-first (delete-dups
                                                     (seq-filter
                                                      (lambda (item)
                                                        (not (string-empty-p item)))
                                                      (ring-elements comint-input-ring))))))
                               (inhibit-read-only t)
                               (qwen-chat-shell-prompt-query-response-style 'inline))
                      (erase-buffer)
                      (insert (propertize (concat prompt "\n\n") 'face font-lock-doc-face))
                      (qwen-chat-shell-send-to-buffer prompt))))
      (define-key view-mode-map (kbd "n")
                  (lambda ()
                    (interactive)
                    (call-interactively #'qwen-chat-shell-next-source-block)
                    (when-let ((block (qwen-chat-shell-markdown-block-at-point)))
                      (set-mark (map-elt block 'end))
                      (goto-char (map-elt block 'start)))))
      (define-key view-mode-map (kbd "p")
                  (lambda ()
                    (interactive)
                    (call-interactively #'qwen-chat-shell-previous-source-block)
                    (when-let ((block (qwen-chat-shell-markdown-block-at-point)))
                      (set-mark (map-elt block 'end))
                      (goto-char (map-elt block 'start)))))
      (define-key view-mode-map (kbd "r") ;; reply
                  (lambda ()
                    (interactive)
                    (with-current-buffer (qwen-chat-shell--primary-buffer)
                      (when shell-maker--busy
                        (user-error "Busy, please wait")))
                    (view-mode -1)
                    (erase-buffer)))
      (define-key view-mode-map (kbd "e") ;; show entire snippet
                  (lambda ()
                    (interactive)
                    (with-current-buffer (qwen-chat-shell--primary-buffer)
                      (when shell-maker--busy
                        (user-error "Busy, please wait")))
                    (let ((prompt "show entire snippet")
                          (inhibit-read-only t)
                          (qwen-chat-shell-prompt-query-response-style 'inline))
                      (erase-buffer)
                      (insert (propertize (concat prompt "\n\n") 'face font-lock-doc-face))
                      (qwen-chat-shell-send-to-buffer prompt))))
      (define-key view-mode-map (kbd "o") ;; show other buffer (ie. the shell itself)
                  (lambda ()
                    (interactive)
                    (switch-to-buffer (qwen-chat-shell--primary-buffer))))
      (local-set-key (kbd "C-c C-k")
                     (lambda ()
                       (interactive)
                       (quit-window t (get-buffer-window buffer))
                       (message "exit")))
      (setq qwen-chat-shell--ring-index nil)
      (local-set-key (kbd "M-p") (lambda ()
                                   (interactive)
                                   (unless view-mode
                                     (let* ((ring (with-current-buffer (qwen-chat-shell--primary-buffer)
                                                    (seq-filter
                                                     (lambda (item)
                                                       (not (string-empty-p item)))
                                                     (ring-elements comint-input-ring))))
                                            (next-index (unless (seq-empty-p ring)
                                                          (if qwen-chat-shell--ring-index
                                                              (1+ qwen-chat-shell--ring-index)
                                                            0))))
                                       (let ((prompt (buffer-string)))
                                         (with-current-buffer (qwen-chat-shell--primary-buffer)
                                           (unless (ring-member comint-input-ring prompt)
                                             (ring-insert comint-input-ring prompt))))
                                       (if next-index
                                           (if (>= next-index (seq-length ring))
                                               (setq qwen-chat-shell--ring-index (1- (seq-length ring)))
                                             (setq qwen-chat-shell--ring-index next-index))
                                         (setq qwen-chat-shell--ring-index nil))
                                       (when qwen-chat-shell--ring-index
                                         (erase-buffer)
                                         (insert (seq-elt ring qwen-chat-shell--ring-index)))))))
      (local-set-key (kbd "M-n") (lambda ()
                                   (interactive)
                                   (unless view-mode
                                     (let* ((ring (with-current-buffer (qwen-chat-shell--primary-buffer)
                                                    (seq-filter
                                                     (lambda (item)
                                                       (not (string-empty-p item)))
                                                     (ring-elements comint-input-ring))))
                                            (next-index (unless (seq-empty-p ring)
                                                          (if qwen-chat-shell--ring-index
                                                              (1- qwen-chat-shell--ring-index)
                                                            0))))
                                       (if next-index
                                           (if (< next-index 0)
                                               (setq qwen-chat-shell--ring-index nil)
                                             (setq qwen-chat-shell--ring-index next-index))
                                         (setq qwen-chat-shell--ring-index nil))
                                       (when qwen-chat-shell--ring-index
                                         (erase-buffer)
                                         (insert (seq-elt ring qwen-chat-shell--ring-index)))))))
      (local-set-key (kbd "C-M-h") (lambda ()
                                     (interactive)
                                     (when-let ((block (qwen-chat-shell-markdown-block-at-point)))
                                       (set-mark (map-elt block 'end))
                                       (goto-char (map-elt block 'start)))))
      (local-set-key (kbd "C-c C-n") #'qwen-chat-shell-next-source-block)
      (local-set-key (kbd "C-c C-p") #'qwen-chat-shell-previous-source-block)
      (local-set-key (kbd "M-r")
                     (lambda ()
                       (interactive)
                       (let ((candidate (with-current-buffer (qwen-chat-shell--primary-buffer)
                                          (completing-read
                                           "History: "
                                           (delete-dups
                                            (seq-filter
                                             (lambda (item)
                                               (not (string-empty-p item)))
                                             (ring-elements comint-input-ring))) nil t))))
                         (insert candidate))))
      (local-set-key (kbd "C-c C-c")
                     (lambda ()
                       (interactive)
                       (with-current-buffer (qwen-chat-shell--primary-buffer)
                         (when shell-maker--busy
                           (unless (y-or-n-p "Abort?")
                             (cl-return))
                           (shell-maker-interrupt t)
                           (with-current-buffer buffer
                             (progn
                               (view-mode -1)
                               (erase-buffer)))
                           (user-error "Aborted")))
                       (when (qwen-chat-shell-block-action-at-point)
                         (qwen-chat-shell-execute-block-action-at-point)
                         (cl-return))
                       (when (string-empty-p
                              (string-trim
                               (buffer-substring-no-properties
                                (point-min) (point-max))))
                         (erase-buffer)
                         (user-error "Nothing to send"))
                       (if view-mode
                           (progn
                             (view-mode -1)
                             (erase-buffer)
                             (message instructions))
                         (setq prompt
                               (string-trim
                                (buffer-substring-no-properties
                                 (point-min) (point-max))))
                         (erase-buffer)
                         (insert (propertize (concat prompt "\n\n") 'face font-lock-doc-face))
                         (view-mode +1)
                         (setq view-exit-action 'kill-buffer)
                         (when (string-equal prompt "clear")
                           (view-mode -1)
                           (erase-buffer))
                         (if exit-on-submit
                             (let ((view-exit-action nil)
                                   (qwen-chat-shell-prompt-query-response-style 'shell))
                               (quit-window t (get-buffer-window buffer))
                               (qwen-chat-shell-send-to-buffer prompt))
                           (let ((qwen-chat-shell-prompt-query-response-style 'inline))
                             (qwen-chat-shell-send-to-buffer prompt))))))
      (message instructions))
    (pop-to-buffer buffer-name)))

(defun qwen-chat-shell-prompt-appending-kill-ring ()
  "Make a model request from the minibuffer appending kill ring."
  (interactive)
  (unless qwen-chat-shell--prompt-history
    (setq qwen-chat-shell--prompt-history
          qwen-chat-shell-default-prompts))
  (let ((prompt (funcall shell-maker-read-string-function
                         (concat
                          "[appending kill ring] "
                          (qwen-chat-shell--minibuffer-prompt))
                         'qwen-chat-shell--prompt-history)))
    (qwen-chat-shell-send-to-buffer
     (concat prompt "\n\n"
             (current-kill 0)) nil)))

(defun qwen-chat-shell-describe-code ()
  "Describe code from region using LLM."
  (interactive)
  (unless (region-active-p)
    (user-error "No region active"))
  (let ((overlay-blocks (derived-mode-p 'prog-mode)))
    (qwen-chat-shell-send-to-buffer
     (concat qwen-chat-shell-prompt-header-describe-code
             "\n\n"
             (if overlay-blocks
                 (format "``` %s\n"
                         (string-remove-suffix "-mode" (format "%s" major-mode)))
               "")
             (buffer-substring (region-beginning) (region-end))
             (if overlay-blocks
                 "\n```"
               "")) nil)
    (when overlay-blocks
      (with-current-buffer
          (qwen-chat-shell--primary-buffer)
        (qwen-chat-shell--put-source-block-overlays)))))

(defun qwen-chat-shell-send-region-with-header (header)
  "Send text with HEADER from region using LLM."
  (unless (region-active-p)
    (user-error "No region active"))
  (let ((question (concat header "\n\n" (buffer-substring (region-beginning) (region-end)))))
    (qwen-chat-shell-send-to-buffer question nil)))

(defun qwen-chat-shell-refactor-code ()
  "Refactor code from region using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-refactor-code))

(defun qwen-chat-shell-write-git-commit ()
  "Write commit from region using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-write-git-commit))

(defun qwen-chat-shell-generate-unit-test ()
  "Generate unit-test for the code from region using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-generate-unit-test))

(defun qwen-chat-shell-proofread-region ()
  "Proofread English from region using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-proofread-region))

(defun qwen-chat-shell-translate-to-english ()
  "Translate the content in the region to English using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-translate-to-english))

(defun qwen-chat-shell-translate-to-chinese ()
  "Translate the content in the region to Chinese using LLM."
  (interactive)
  (qwen-chat-shell-send-region-with-header qwen-chat-shell-prompt-header-translate-to-chinese))

(defun qwen-chat-shell-eshell-whats-wrong-with-last-command ()
  "Ask LLM what's wrong with the last eshell command."
  (interactive)
  (let ((qwen-chat-shell-prompt-query-response-style 'other-buffer))
    (qwen-chat-shell-send-to-buffer
     (concat qwen-chat-shell-prompt-header-whats-wrong-with-last-command
             "\n\n"
             (buffer-substring-no-properties eshell-last-input-start eshell-last-input-end)
             "\n\n"
             (buffer-substring-no-properties (eshell-beginning-of-output) (eshell-end-of-output))))))

(defun qwen-chat-shell-eshell-summarize-last-command-output ()
  "Ask LLM to summarize the last command output."
  (interactive)
  (let ((qwen-chat-shell-prompt-query-response-style 'other-buffer))
    (qwen-chat-shell-send-to-buffer
     (concat qwen-chat-shell-prompt-header-eshell-summarize-last-command-output
             "\n\n"
             (buffer-substring-no-properties eshell-last-input-start eshell-last-input-end)
             "\n\n"
             (buffer-substring-no-properties (eshell-beginning-of-output) (eshell-end-of-output))))))

(defun qwen-chat-shell-send-region (review)
  "Send region to LLM.
With prefix REVIEW prompt before sending to LLM."
  (interactive "P")
  (unless (region-active-p)
    (user-error "No region active"))
  (let ((qwen-chat-shell-prompt-query-response-style 'shell)
        (region-text (buffer-substring (region-beginning) (region-end))))
    (qwen-chat-shell-send-to-buffer
     (if review
         (concat "\n\n" region-text)
       region-text) review)))

(defun qwen-chat-shell-send-and-review-region ()
  "Send region to LLM, review before submitting."
  (interactive)
  (qwen-chat-shell-send-region t))

(defun qwen-chat-shell-command-line-from-prompt-file (file-path)
  "Send prompt in FILE-PATH and output to standard output."
  (let ((prompt (with-temp-buffer
                  (insert-file-contents file-path)
                  (buffer-string))))
    (if (string-empty-p (string-trim prompt))
        (princ (format "Could not read prompt from %s" file-path)
               #'external-debugging-output)
      (qwen-chat-shell-command-line prompt))))

(defun qwen-chat-shell-command-line (prompt)
  "Send PROMPT and output to standard output."
  (let ((qwen-chat-shell-prompt-query-response-style 'shell)
        (worker-done nil)
        (buffered ""))
    (qwen-chat-shell-send-to-buffer
     prompt nil
     (lambda (_command output _error finished)
       (setq buffered (concat buffered output))
       (when finished
         (setq worker-done t))))
    (while buffered
      (unless (string-empty-p buffered)
        (princ buffered #'external-debugging-output))
      (setq buffered "")
      (when worker-done
        (setq buffered nil))
      (sleep-for 0.1))
    (princ "\n")))

(defun qwen-chat-shell--eshell-last-last-command ()
  "Get second to last eshell command."
  (save-excursion
    (if (derived-mode-p 'eshell-mode)
        (let ((cmd-start)
              (cmd-end))
          ;; Find command start and end positions
          (goto-char eshell-last-output-start)
          (re-search-backward eshell-prompt-regexp nil t)
          (setq cmd-start (point))
          (goto-char eshell-last-output-start)
          (setq cmd-end (point))

          ;; Find output start and end positions
          (goto-char eshell-last-output-start)
          (forward-line 1)
          (re-search-forward eshell-prompt-regexp nil t)
          (forward-line -1)
          (concat "What's wrong with this command?\n\n"
                  (buffer-substring-no-properties cmd-start cmd-end)))
      (message "Current buffer is not an eshell buffer."))))

;; Based on https://emacs.stackexchange.com/a/48215
(defun qwen-chat-shell--source-eshell-string (string)
  "Execute eshell command in STRING."
  (let ((orig (point))
        (here (point-max)))
    (cursor-sensor-mode 1)
    (goto-char (point-max))
    (with-silent-modifications
      ;; FIXME: Use temporary buffer and avoid insert/delete.
      (insert string)
      (goto-char (point-max))
      (throw 'eshell-replace-command
             (prog1
                 (list 'let
                       (list (list 'eshell-command-name (list 'quote "source-string"))
                             (list 'eshell-command-arguments '()))
                       (eshell-parse-command (cons here (point))))
               (delete-region here (point))
               (goto-char orig))))))

(defun qwen-chat-shell-send-to-buffer (text &optional review handler)
  "Send TEXT to *LLM* buffer.
Set REVIEW to make changes before submitting to LLM.

If HANDLER function is set, ignore
`qwen-chat-shell-prompt-query-response-style'."
  (let* ((buffer (cond (handler
                        nil)
                       ((eq qwen-chat-shell-prompt-query-response-style 'inline)
                        (current-buffer))
                       ((eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
                        (let* ((inhibit-read-only t)
                               (other-buffer
                                (get-buffer-create
                                 (concat (qwen-chat-shell--minibuffer-prompt)
                                         (truncate-string-to-width
                                          (nth 0 (split-string text "\n"))
                                          (window-body-width))))))
                          (with-current-buffer other-buffer
                            (erase-buffer))
                          other-buffer))
                       (t
                        nil)))
         (point (point))
         (marker (copy-marker (point)))
         (orig-region-active (region-active-p))
         (no-focus (or (eq qwen-chat-shell-prompt-query-response-style 'inline)
                       (eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
                       handler)))
    (when (region-active-p)
      (setq marker (copy-marker (max (region-beginning)
                                     (region-end)))))
    (if (qwen-chat-shell--primary-buffer)
        (with-current-buffer (qwen-chat-shell--primary-buffer)
          (qwen-chat-shell-start no-focus))
      (qwen-chat-shell-start no-focus t))
    (when (eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
      (with-current-buffer buffer
        (view-mode +1)
        (setq view-exit-action 'kill-buffer)))
    (when (eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
      (unless (assoc (rx "*Qwen>" (zero-or-more not-newline) "*")
                     display-buffer-alist)
        (add-to-list 'display-buffer-alist
                     (cons (rx "*Qwen>" (zero-or-more not-newline) "*")
                           '((display-buffer-below-selected) (split-window-sensibly)))))
      (display-buffer buffer))
    (cl-flet ((send ()
                    (when shell-maker--busy
                      (shell-maker-interrupt nil))
                    (goto-char (point-max))
                    (if review
                        (save-excursion
                          (insert text))
                      (insert text)
                      (shell-maker--send-input
                       (if (or (eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
                               (eq qwen-chat-shell-prompt-query-response-style 'inline))
                           (lambda (_command output error finished)
                             (setq output (or output ""))
                             (when (buffer-live-p buffer)
                               (with-current-buffer buffer
                                 (if error
                                     (unless (string-empty-p (string-trim output))
                                       (message "%s" output))
                                   (let ((inhibit-read-only t))
                                     (save-excursion
                                       (if orig-region-active
                                           (progn
                                             (goto-char marker)
                                             (when (eq (marker-position marker)
                                                       point)
                                               (insert "\n\n")
                                               (set-marker marker (+ 2 (marker-position marker))))
                                             (insert output)
                                             (set-marker marker (+ (length output)
                                                                   (marker-position marker))))
                                         (goto-char marker)
                                         (insert output)
                                         (set-marker marker (+ (length output)
                                                               (marker-position marker)))))))
                                 (when (and finished
                                            (eq qwen-chat-shell-prompt-query-response-style 'other-buffer))
                                   (qwen-chat-shell--put-source-block-overlays)))))
                         (or handler (lambda (_command _output _error _finished))))
                       t))))
      (if (or (eq qwen-chat-shell-prompt-query-response-style 'inline)
              (eq qwen-chat-shell-prompt-query-response-style 'other-buffer)
              handler)
          (with-current-buffer (qwen-chat-shell--primary-buffer)
            (goto-char (point-max))
            (send))
        (with-selected-window (get-buffer-window (qwen-chat-shell--primary-buffer))
          (send))))))

(defun qwen-chat-shell-send-to-ielm-buffer (text &optional execute save-excursion)
  "Send TEXT to *ielm* buffer.
Set EXECUTE to automatically execute.
Set SAVE-EXCURSION to prevent point from moving."
  (ielm)
  (with-current-buffer (get-buffer-create "*ielm*")
    (goto-char (point-max))
    (if save-excursion
        (save-excursion
          (insert text))
      (insert text))
    (when execute
      (ielm-return))))

(defun qwen-chat-shell-parse-elisp-code (code)
  "Parse emacs-lisp CODE and return a list of expressions."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (let (sexps)
      (while (not (eobp))
        (condition-case nil
            (push (read (current-buffer)) sexps)
          (error nil)))
      (reverse sexps))))

(defun qwen-chat-shell-split-elisp-expressions (code)
  "Split emacs-lisp CODE into a list of stringified expressions."
  (mapcar
   (lambda (form)
     (prin1-to-string form))
   (qwen-chat-shell-parse-elisp-code code)))


(defun qwen-chat-shell-make-request-data (messages &optional model temperature other-params)
  "Make request data from MESSAGES, MODEL, TEMPERATURE, and OTHER-PARAMS."
  (let ((request-data `((model . ,(or model
                                      (qwen-chat-shell-current-model)))
                        (messages . ,(vconcat ;; Vector for json
                                      messages)))))
    (when (or temperature qwen-chat-shell-model-temperature)
      (push `(temperature . ,(or temperature qwen-chat-shell-model-temperature))
            request-data))
    (when other-params
      (push other-params
            request-data))
    request-data))

(defun qwen-chat-shell-post-messages (messages response-extractor &optional model callback error-callback temperature other-params)
  "Make a single LLM request with MESSAGES and RESPONSE-EXTRACTOR.

`qwen-chat-shell--extract-dashscope-response' typically used as extractor.

Optionally pass model MODEL, CALLBACK, ERROR-CALLBACK, TEMPERATURE
and OTHER-PARAMS.

OTHER-PARAMS are appended to the json object at the top level.

If CALLBACK or ERROR-CALLBACK are missing, execute synchronously.

For example:

\(qwen-chat-shell-post-messages
 `(((role . \"user\")
    (content . \"hello\")))
 \"qwen-turbo\"
 (lambda (response)
   (message \"%s\" response))
 (lambda (error)
   (message \"%s\" error)))"
  (if (and callback error-callback)
      (progn
        (with-temp-buffer
          (setq-local shell-maker--config
                      qwen-chat-shell--config)
          (shell-maker-async-shell-command
           (qwen-chat-shell--make-curl-request-command-list
            (qwen-chat-shell-make-request-data messages model temperature other-params))
           nil ;; streaming
           (or response-extractor #'qwen-chat-shell--extract-dashscope-response)
           callback
           error-callback)))
    (with-temp-buffer
      (setq-local shell-maker--config
                  qwen-chat-shell--config)
      (let* ((buffer (current-buffer))
             (command
              (qwen-chat-shell--make-curl-request-command-list
               (let ((request-data `((model . ,(or model
                                                   (qwen-chat-shell-current-model)))
                                     (messages . ,(vconcat ;; Vector for json
                                                   messages)))))
                 (when (or temperature qwen-chat-shell-model-temperature)
                   (push `(temperature . ,(or temperature qwen-chat-shell-model-temperature))
                         request-data))
                 (when other-params
                   (push other-params
                         request-data))
                 request-data)))
             (config qwen-chat-shell--config)
             (status (progn
                       (shell-maker--write-output-to-log-buffer "// Request\n\n" config)
                       (shell-maker--write-output-to-log-buffer (string-join command " ") config)
                       (shell-maker--write-output-to-log-buffer "\n\n" config)
                       (apply #'call-process (seq-first command) nil buffer nil (cdr command))))
             (data (buffer-substring-no-properties (point-min) (point-max)))
             (response (qwen-chat-shell--extract-dashscope-response data)))
        (shell-maker--write-output-to-log-buffer (format "// Data (status: %d)\n\n" status) config)
        (shell-maker--write-output-to-log-buffer data config)
        (shell-maker--write-output-to-log-buffer "\n\n" config)
        (shell-maker--write-output-to-log-buffer "// Response\n\n" config)
        (shell-maker--write-output-to-log-buffer response config)
        (shell-maker--write-output-to-log-buffer "\n\n" config)
        response))))

;; TODO: support this
;; (defun qwen-chat-shell-describe-image ()
;;   "Request qwen-vl-plus to describe image.

;; When visiting a buffer with an image, send that.

;; If in a `dired' buffer, use selection (single image only for now)."
;;   (interactive)
;;   (let* ((file (qwen-chat-shell--current-file))
;;          (extension (downcase (file-name-extension file))))
;;     (unless (seq-contains-p '("jpg" "jpeg" "png" "webp" "gif") extension)
;;       (user-error "Must be user either .jpg, .jpeg, .png, .webp or .gif file"))
;;     (qwen-chat-shell-vision-make-request
;;      (read-string "Prompt (default \"这个图片里有什么?\"): " nil nil "这个图片里有什么?")
;;      file)))

(defun qwen-chat-shell--current-file ()
  "Return buffer file (if available) or Dired selected file."
  (when (use-region-p)
    (user-error "No region selection supported"))
  (if (buffer-file-name)
      (buffer-file-name)
    (let* ((dired-files (dired-get-marked-files))
           (file (seq-first dired-files)))
      (unless dired-files
        (user-error "No file selected"))
      (when (> (length dired-files) 1)
        (user-error "Only one file selection supported"))
      file)))

(cl-defun qwen-chat-shell-vision-make-request (prompt url-path &key on-success on-failure)
  "Make a vision request using PROMPT and URL-PATH.

PROMPT can be somethign like: \"请详细描述一下图片里有什么\".
URL-PATH can be either a local file path or an http:// URL.

Optionally pass ON-SUCCESS and ON-FAILURE, like:

\(lambda (response)
  (message response))

\(lambda (error)
  (message error))"
  (let* ((url (if (string-prefix-p "http" url-path)
                  url-path
                (unless (file-exists-p url-path)
                  (error "File not found"))
                (concat "data:image/jpeg;base64,"
                        (with-temp-buffer
                          (insert-file-contents-literally url-path)
                          (base64-encode-region (point-min) (point-max) t)
                          (buffer-string)))))
         (messages
          (vconcat ;; Convert to vector for json
           (append
            `(((role . "user")
               (content . ,(vconcat
                            `(((type . "text")
                               (text . ,prompt))
                              ((type . "image_url")
                               (image_url . ,url)))))))))))
    (message "Requesting...")
    (qwen-chat-shell-post-messages
     messages
     #'qwen-chat-shell--extract-dashscope-response
     "qwen-vl-plus"
     (if on-success
         (lambda (response _partial)
           (funcall on-success response))
       (lambda (response _partial)
         (message response)))
     (or on-failure (lambda (error)
                      (message error)))
     nil '(max_tokens . 300))))

(defun qwen-chat-shell-post-prompt (prompt &optional response-extractor model callback error-callback temperature other-params)
  "Make a single LLM request with PROMPT.
Optionally pass model RESPONSE-EXTRACTOR, MODEL, CALLBACK,
ERROR-CALLBACK, TEMPERATURE, and OTHER-PARAMS.

`qwen-chat-shell--extract-dashscope-response' typically used as extractor.

If CALLBACK or ERROR-CALLBACK are missing, execute synchronously.

OTHER-PARAMS are appended to the json object at the top level.

For example:

\(qwen-chat-shell-post-prompt
 \"hello\"
 nil
 \"qwen-turbo\"
 (lambda (response more-pending)
   (message \"%s\" response))
 (lambda (error)
   (message \"%s\" error)))."
  (qwen-chat-shell-post-messages `(((role . "user")
                                  (content . ,prompt)))
                               (or response-extractor #'qwen-chat-shell--extract-dashscope-response)
                               model
                               callback
                               error-callback
                               temperature
                               other-params))

(defun qwen-chat-shell-dashscope-key ()
  "Get the Dashscope key."
  (cond ((stringp qwen-chat-shell-dashscope-key)
         qwen-chat-shell-dashscope-key)
        ((functionp qwen-chat-shell-dashscope-key)
         (condition-case _err
             (funcall qwen-chat-shell-dashscope-key)
           (error
            "KEY-NOT-FOUND")))
        (t
         nil)))

(defun qwen-chat-shell--api-url ()
  "The complete URL Dashcope's API.

`qwen-chat-shell--api-url' =
   `qwen-chat-shell--api-url-base' + `qwen-chat-shell--api-url-path'"
  (concat qwen-chat-shell-api-url-base qwen-chat-shell-api-url-path))

(defun qwen-chat-shell--json-request-file ()
  "JSON request written to this file prior to sending."
  (concat
   (file-name-as-directory
    (shell-maker-files-path shell-maker--config))
   "request.json"))

(defun qwen-chat-shell--make-curl-request-command-list (request-data)
  "Build LLM curl command list using REQUEST-DATA."
  (let ((json-path (qwen-chat-shell--json-request-file)))
    (with-temp-file json-path
      (when (eq system-type 'windows-nt)
        (setq-local buffer-file-coding-system 'utf-8))
      (insert (shell-maker--json-encode request-data)))
    (append (list "curl" (qwen-chat-shell--api-url))
            qwen-chat-shell-additional-curl-options
            (list "--fail-with-body"
                  "--no-progress-meter"
                  "-m" (number-to-string qwen-chat-shell-request-timeout)
                  "-H" "Content-Type: application/json; charset=utf-8"
                  "-H" (funcall qwen-chat-shell-auth-header)
                  "-d" (format "@%s" json-path)))))

(defun qwen-chat-shell--make-payload (history)
  "Create the request payload from HISTORY."
  (setq history
        (vconcat ;; Vector for json
         (qwen-chat-shell--user-assistant-messages
          (last history
                (qwen-chat-shell--unpaired-length
                 (if (functionp qwen-chat-shell-transmitted-context-length)
                     (funcall qwen-chat-shell-transmitted-context-length
                              (qwen-chat-shell-current-model) history)
                   qwen-chat-shell-transmitted-context-length))))))
  (let ((request-data `((model . ,(qwen-chat-shell-current-model))
                        (messages . ,(if (qwen-chat-shell-system-prompt)
                                         (vconcat ;; Vector for json
                                          (list
                                           (list
                                            (cons 'role "system")
                                            (cons 'content (qwen-chat-shell-system-prompt))))
                                          history)
                                       history)))))
    (when qwen-chat-shell-model-temperature
      (push `(temperature . ,qwen-chat-shell-model-temperature) request-data))
    (when qwen-chat-shell-streaming
      (push `(stream . t) request-data))
    request-data))

(defun qwen-chat-shell-get-model-param-num (model)
  "Get the parameter number from the MODEL name."
    (let ((param
           (string-to-number (string-remove-suffix "b" (car (cdr (split-string model "-")))))))
      (if (/= param 0)
          param
        (error "Cannot get paramter number from model name '%s'" model))))

(defun qwen-chat-shell--approximate-context-length (model messages)
  "Approximate the context length using MODEL and MESSAGES.
Reference:
1. Qwen commercial series: https://help.aliyun.com/zh/dashscope/\
developer-reference/model-introduction
2. Qwen Open Source series: https://help.aliyun.com/zh/dashscope/\
developer-reference/tongyi-qianwen-7b-14b-72b-api-detailes"
  (let* ((tokens-per-message)
         (max-tokens)
         (original-length (floor (/ (length messages) 2)))
         (context-length original-length))
    ;; Remove "ft:" from fine-tuned models and recognize as usual
    (setq model (string-remove-prefix "ft:" model))
    (cond
     ((string-equal "qwen-turbo" model)
      (setq tokens-per-message 4
            max-tokens 5800))
     ((string-equal "qwen-plus" model)
      (setq tokens-per-message 4
            max-tokens 29800))
     ((string-equal "qwen-max-longcontext" model)
      (setq tokens-per-message 4
            max-tokens 27800))
     ((string-equal "qwen-max" model)
      (setq tokens-per-message 4
            max-tokens 5800))
     ((string-equal "codeqwen" model)
      (setq tokens-per-message 4
            max-tokens 55800))
     ((string-equal "qwen-1.8b-longcontext-chat" model)
      (setq tokens-per-message 4
            max-tokens 29800))
     ((string-equal "qwen2-57b-a14b-instruct" model)
      (setq tokens-per-message 4
            max-tokens 30000))
     ((string-prefix-p "qwen2-" model)
      (let ((param-num (qwen-chat-shell-get-model-param-num model)))
        (if (<= param-num 2)
            (setq tokens-per-message 4 max-tokens 30000) ; 30720
          (setq tokens-per-message 4 max-tokens 127800)))) ; 128k
     ((let ((param-num (qwen-chat-shell-get-model-param-num model)))
        (if (<= param-num 14)
            (setq tokens-per-message 4 max-tokens 5800) ; 6K
          (setq tokens-per-message 4 max-tokens 31800)))) ; 32K
     (t
      (error "Don't know '%s', so can't approximate context length" model)))
    (while (> (qwen-chat-shell--num-tokens-from-messages
               tokens-per-message messages)
              max-tokens)
      (setq messages (cdr messages)))
    (setq context-length (floor (/ (length messages) 2)))
    (unless (eq original-length context-length)
      (message "Warning: qwen-chat-shell context clipped"))
    context-length))

;; Very rough token approximation loosely based on num_tokens_from_messages from:
;; https://github.com/openai/openai-cookbook/blob/main/examples/How_to_count_tokens_with_tiktoken.ipynb
(defun qwen-chat-shell--num-tokens-from-messages (tokens-per-message messages)
  "Approximate number of tokens in MESSAGES using TOKENS-PER-MESSAGE."
  (let ((num-tokens 0))
    (dolist (message messages)
      (setq num-tokens (+ num-tokens tokens-per-message))
      (setq num-tokens (+ num-tokens (/ (length (cdr message)) tokens-per-message))))
    ;; Every reply is primed with <|start|>assistant<|message|>
    (setq num-tokens (+ num-tokens 3))
    num-tokens))

(defun qwen-chat-shell--extract-dashscope-response (json)
  "Extract LLM response from JSON."
  (if (eq (type-of json) 'cons)
      (let-alist json ;; already parsed
        (or (unless (seq-empty-p .choices)
              (let-alist (seq-first .choices)
                (or .delta.content
                    .message.content)))
            .error.message
            ""))
    (if-let (parsed (shell-maker--json-parse-string json))
        (string-trim
         (let-alist parsed
           (unless (seq-empty-p .choices)
             (let-alist (seq-first .choices)
               .message.content))))
      (if-let (parsed-error (shell-maker--json-parse-string-filtering
                             json "^curl:.*\n?"))
          (let-alist parsed-error
            .error.message)))))

(defun qwen-chat-shell-restore-session-from-transcript ()
  "Restore session from transcript.

EXPERIMENTAL from `chatgpt-shell'."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (let* ((dir (when shell-maker-transcript-default-path
                (file-name-as-directory shell-maker-transcript-default-path)))
         (path (read-file-name "Restore from: " dir nil t))
         (prompt-regexp (shell-maker-prompt-regexp shell-maker--config))
         (history (with-temp-buffer
                    (insert-file-contents path)
                    (qwen-chat-shell--extract-history
                     (buffer-substring-no-properties
                      (point-min) (point-max))
                     prompt-regexp)))
         (execute-command (shell-maker-config-execute-command
                           shell-maker--config))
         (validate-command (shell-maker-config-validate-command
                            shell-maker--config))
         (command)
         (response)
         (failed))
    ;; Momentarily overrides request handling to replay all commands
    ;; read from file so comint treats all commands/outputs like
    ;; any other command.
    (unwind-protect
        (progn
          (setf (shell-maker-config-validate-command shell-maker--config) nil)
          (setf (shell-maker-config-execute-command shell-maker--config)
                (lambda (_command _history callback _error-callback)
                  (setq response (car history))
                  (setq history (cdr history))
                  (when response
                    (unless (string-equal (map-elt response 'role)
                                          "assistant")
                      (setq failed t)
                      (user-error "Invalid transcript"))
                    (funcall callback (map-elt response 'content) nil)
                    (setq command (car history))
                    (setq history (cdr history))
                    (when command
                      (goto-char (point-max))
                      (insert (map-elt command 'content))
                      (shell-maker--send-input)))))
          (goto-char (point-max))
          (comint-clear-buffer)
          (setq command (car history))
          (setq history (cdr history))
          (when command
            (unless (string-equal (map-elt command 'role)
                                  "user")
              (setq failed t)
              (user-error "Invalid transcript"))
            (goto-char (point-max))
            (insert (map-elt command 'content))
            (shell-maker--send-input)))
      (if failed
          (setq shell-maker--file nil)
        (setq shell-maker--file path))
      (setq shell-maker--busy nil)
      (setf (shell-maker-config-validate-command shell-maker--config)
            validate-command)
      (setf (shell-maker-config-execute-command shell-maker--config)
            execute-command)))
  (goto-char (point-max)))

(defun qwen-chat-shell--fontify-source-block (quotes1-start quotes1-end lang
lang-start lang-end body-start body-end quotes2-start quotes2-end)
  "Fontify a source block.
Use QUOTES1-START QUOTES1-END LANG LANG-START LANG-END BODY-START
 BODY-END QUOTES2-START and QUOTES2-END."
  ;; Hide ```
  (overlay-put (make-overlay quotes1-start
                             quotes1-end) 'invisible 'qwen-chat-shell)
  (overlay-put (make-overlay quotes2-start
                             quotes2-end) 'invisible 'qwen-chat-shell)
  (unless (eq lang-start lang-end)
    (overlay-put (make-overlay lang-start
                               lang-end) 'face '(:box t))
    (overlay-put (make-overlay lang-end
                               (1+ lang-end)) 'display "\n\n"))
  (let ((lang-mode (intern (concat (or
                                    (qwen-chat-shell--resolve-internal-language lang)
                                    (downcase (string-trim lang)))
                                   "-mode")))
        (string (buffer-substring-no-properties body-start body-end))
        (buf (if (and (boundp 'shell-maker--config)
                      shell-maker--config)
                 (shell-maker-buffer shell-maker--config)
               (current-buffer)))
        (pos 0)
        (props)
        (overlay)
        (propertized-text))
    (if (fboundp lang-mode)
        (progn
          (setq propertized-text
                (with-current-buffer
                    (get-buffer-create
                     (format " *qwen-chat-shell-fontification:%s*" lang-mode))
                  (let ((inhibit-modification-hooks nil)
                        (inhibit-message t))
                    (erase-buffer)
                    ;; Additional space ensures property change.
                    (insert string " ")
                    (funcall lang-mode)
                    (font-lock-ensure))
                  (buffer-string)))
          (while (< pos (length propertized-text))
            (setq props (text-properties-at pos propertized-text))
            (setq overlay (make-overlay (+ body-start pos)
                                        (+ body-start (1+ pos))
                                        buf))
            (overlay-put overlay 'face (plist-get props 'face))
            (setq pos (1+ pos))))
      (overlay-put (make-overlay body-start body-end buf)
                   'face 'font-lock-doc-markup-face))))

(defun qwen-chat-shell--fontify-link (start end title-start title-end url-start url-end)
  "Fontify a markdown link.
Use START END TITLE-START TITLE-END URL-START URL-END."
  ;; Hide markup before
  (overlay-put (make-overlay start title-start) 'invisible 'qwen-chat-shell)
  ;; Show title as link
  (overlay-put (make-overlay title-start title-end) 'face 'link)
  ;; Make RET open the URL
  (define-key (let ((map (make-sparse-keymap)))
                (define-key map [mouse-1]
                  (lambda () (interactive)
                    (browse-url (buffer-substring-no-properties url-start url-end))))
                (define-key map (kbd "RET")
                  (lambda () (interactive)
                    (browse-url (buffer-substring-no-properties url-start url-end))))
                (overlay-put (make-overlay title-start title-end) 'keymap map)
                map)
    [remap self-insert-command] 'ignore)
  ;; Hide markup after
  (overlay-put (make-overlay title-end end) 'invisible 'qwen-chat-shell))

(defun qwen-chat-shell--fontify-bold (start end text-start text-end)
  "Fontify a markdown bold.
Use START END TEXT-START TEXT-END."
  ;; Hide markup before
  (overlay-put (make-overlay start text-start) 'invisible 'qwen-chat-shell)
  ;; Show title as bold
  (overlay-put (make-overlay text-start text-end) 'face 'bold)
  ;; Hide markup after
  (overlay-put (make-overlay text-end end) 'invisible 'qwen-chat-shell))

(defun qwen-chat-shell--fontify-header (start _end level-start level-end title-start title-end)
  "Fontify a markdown header.
Use START END LEVEL-START LEVEL-END TITLE-START TITLE-END."
  ;; Hide markup before
  (overlay-put (make-overlay start title-start) 'invisible 'qwen-chat-shell)
  ;; Show title as header
  (overlay-put (make-overlay title-start title-end) 'face
               (cond ((eq (- level-end level-start) 1)
                      'org-level-1)
                     ((eq (- level-end level-start) 2)
                      'org-level-2)
                     ((eq (- level-end level-start) 3)
                      'org-level-3)
                     ((eq (- level-end level-start) 4)
                      'org-level-4)
                     ((eq (- level-end level-start) 5)
                      'org-level-5)
                     ((eq (- level-end level-start) 6)
                      'org-level-6)
                     ((eq (- level-end level-start) 7)
                      'org-level-7)
                     ((eq (- level-end level-start) 8)
                      'org-level-8)
                     (t
                      'org-level-1))))

(defun qwen-chat-shell--fontify-italic (start end text-start text-end)
  "Fontify a markdown italic.
Use START END TEXT-START TEXT-END."
  ;; Hide markup before
  (overlay-put (make-overlay start text-start) 'invisible 'qwen-chat-shell)
  ;; Show title as italic
  (overlay-put (make-overlay text-start text-end) 'face 'italic)
  ;; Hide markup after
  (overlay-put (make-overlay text-end end) 'invisible 'qwen-chat-shell))

(defun qwen-chat-shell--fontify-strikethrough (start end text-start text-end)
  "Fontify a markdown strikethrough.
Use START END TEXT-START TEXT-END."
  ;; Hide markup before
  (overlay-put (make-overlay start text-start) 'invisible 'qwen-chat-shell)
  ;; Show title as strikethrough
  (overlay-put (make-overlay text-start text-end) 'face '(:strike-through t))
  ;; Hide markup after
  (overlay-put (make-overlay text-end end) 'invisible 'qwen-chat-shell))

(defun qwen-chat-shell--fontify-inline-code (body-start body-end)
  "Fontify a source block.
Use QUOTES1-START QUOTES1-END LANG LANG-START LANG-END BODY-START
 BODY-END QUOTES2-START and QUOTES2-END."
  ;; Hide ```
  (overlay-put (make-overlay (1- body-start)
                             body-start) 'invisible 'qwen-chat-shell)
  (overlay-put (make-overlay body-end
                             (1+ body-end)) 'invisible 'qwen-chat-shell)
  (overlay-put (make-overlay body-start body-end
                             (if (and (boundp 'shell-maker--config)
                                      shell-maker--config)
                                 (shell-maker-buffer shell-maker--config)
                               (current-buffer)))
               'face 'font-lock-doc-markup-face))

(defun qwen-chat-shell-rename-block-at-point ()
  "Rename block at point (perhaps a different language)."
  (interactive)
  (save-excursion
    (if-let ((block (qwen-chat-shell-markdown-block-at-point)))
        (if (map-elt block 'language)
            (perform-replace (map-elt block 'language)
                             (read-string "Name: " nil nil "") nil nil nil nil nil
                             (map-elt block 'language-start) (map-elt block 'language-end))
          (let ((new-name (read-string "Name: " nil nil "")))
            (goto-char (map-elt block 'language-start))
            (insert new-name)
            (qwen-chat-shell--put-source-block-overlays)))
      (user-error "No block at point"))))

(defun qwen-chat-shell-remove-block-overlays ()
  "Remove block overlays.  Handy for renaming blocks."
  (interactive)
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (delete-overlay overlay)))

(defun qwen-chat-shell-refresh-rendering ()
  "Refresh markdown rendering by re-applying to entire buffer."
  (interactive)
  (qwen-chat-shell--put-source-block-overlays))

(defun qwen-chat-shell--put-source-block-overlays ()
  "Put overlays for all source blocks."
  (when qwen-chat-shell-highlight-blocks
    (let* ((source-blocks (qwen-chat-shell--source-blocks))
           (avoid-ranges (seq-map (lambda (block)
                                    (map-elt block 'body))
                                  source-blocks)))
      (dolist (overlay (overlays-in (point-min) (point-max)))
        (delete-overlay overlay))
      (dolist (block source-blocks)
        (qwen-chat-shell--fontify-source-block
         (car (map-elt block 'start))
         (cdr (map-elt block 'start))
         (buffer-substring-no-properties (car (map-elt block 'language))
                                         (cdr (map-elt block 'language)))
         (car (map-elt block 'language))
         (cdr (map-elt block 'language))
         (car (map-elt block 'body))
         (cdr (map-elt block 'body))
         (car (map-elt block 'end))
         (cdr (map-elt block 'end))))
      (dolist (link (qwen-chat-shell--markdown-links avoid-ranges))
        (qwen-chat-shell--fontify-link
         (map-elt link 'start)
         (map-elt link 'end)
         (car (map-elt link 'title))
         (cdr (map-elt link 'title))
         (car (map-elt link 'url))
         (cdr (map-elt link 'url))))
      (dolist (header (qwen-chat-shell--markdown-headers avoid-ranges))
        (qwen-chat-shell--fontify-header
         (map-elt header 'start)
         (map-elt header 'end)
         (car (map-elt header 'level))
         (cdr (map-elt header 'level))
         (car (map-elt header 'title))
         (cdr (map-elt header 'title))))
      (dolist (bold (qwen-chat-shell--markdown-bolds avoid-ranges))
        (qwen-chat-shell--fontify-bold
         (map-elt bold 'start)
         (map-elt bold 'end)
         (car (map-elt bold 'text))
         (cdr (map-elt bold 'text))))
      (dolist (italic (qwen-chat-shell--markdown-italics avoid-ranges))
        (qwen-chat-shell--fontify-italic
         (map-elt italic 'start)
         (map-elt italic 'end)
         (car (map-elt italic 'text))
         (cdr (map-elt italic 'text))))
      (dolist (strikethrough (qwen-chat-shell--markdown-strikethroughs avoid-ranges))
        (qwen-chat-shell--fontify-strikethrough
         (map-elt strikethrough 'start)
         (map-elt strikethrough 'end)
         (car (map-elt strikethrough 'text))
         (cdr (map-elt strikethrough 'text))))
      (dolist (inline-code (qwen-chat-shell--markdown-inline-codes avoid-ranges))
        (qwen-chat-shell--fontify-inline-code
         (car (map-elt inline-code 'body))
         (cdr (map-elt inline-code 'body)))))))

(defun qwen-chat-shell--unpaired-length (length)
  "Expand LENGTH to include paired responses.

Each request has a response, so double LENGTH if set.

Add one for current request (without response).

If no LENGTH set, use 2048."
  (if length
      (1+ (* 2 length))
    2048))

(defun qwen-chat-shell-view-at-point ()
  "View prompt and output at point in a separate buffer."
  (interactive)
  (unless (eq major-mode 'qwen-chat-shell-mode)
    (user-error "Not in a shell"))
  (let ((prompt-pos (save-excursion
                      (goto-char (process-mark
                                  (get-buffer-process (current-buffer))))
                      (point)))
        (buf))
    (save-excursion
      (when (>= (point) prompt-pos)
        (goto-char prompt-pos)
        (forward-line -1)
        (end-of-line))
      (let* ((items (qwen-chat-shell--user-assistant-messages
                     (shell-maker--command-and-response-at-point)))
             (command (string-trim (or (map-elt (seq-first items) 'content) "")))
             (response (string-trim (or (map-elt (car (last items)) 'content) ""))))
        (setq buf (generate-new-buffer (if command
                                           (concat
                                            (buffer-name (current-buffer)) "> "
                                            ;; Only the first line of prompt.
                                            (seq-first (split-string command "\n")))
                                         (concat (buffer-name (current-buffer)) "> "
                                                 "(no prompt)"))))
        (when (seq-empty-p items)
          (user-error "Nothing to view"))
        (with-current-buffer buf
          (save-excursion
            (insert (propertize (or command "") 'face font-lock-doc-face))
            (when (and command response)
              (insert "\n\n"))
            (insert (or response "")))
          (qwen-chat-shell--put-source-block-overlays)
          (view-mode +1)
          (setq view-exit-action 'kill-buffer))))
    (switch-to-buffer buf)
    buf))

(defun qwen-chat-shell--extract-history (text prompt-regexp)
  "Extract all command and responses in TEXT with PROMPT-REGEXP."
  (qwen-chat-shell--user-assistant-messages
   (shell-maker--extract-history text prompt-regexp)))

(defun qwen-chat-shell--user-assistant-messages (history)
  "Convert HISTORY to LLM format.

Sequence must be a vector for json serialization.

For example:

 [
   ((role . \"user\") (content . \"hello\"))
   ((role . \"assistant\") (content . \"world\"))
 ]"
  (let ((result))
    (mapc
     (lambda (item)
       (when (car item)
         (push (list (cons 'role "user")
                     (cons 'content (car item))) result))
       (when (cdr item)
         (push (list (cons 'role "assistant")
                     (cons 'content (cdr item))) result)))
     history)
    (nreverse result)))

(defun qwen-chat-shell-run-command (command callback)
  "Run COMMAND list asynchronously and call CALLBACK function.

CALLBACK can be like:

\(lambda (success output)
  (message \"%s\" output))"
  (let* ((buffer (generate-new-buffer "*run command*"))
         (proc (apply #'start-process
                      (append `("exec" ,buffer) command))))
    (set-process-sentinel
     proc
     (lambda (proc _)
       (with-current-buffer buffer
         (funcall callback
                  (equal (process-exit-status proc) 0)
                  (buffer-string))
         (kill-buffer buffer))))))

(defun qwen-chat-shell--resolve-internal-language (language)
  "Resolve external LANGUAGE to internal.

For example \"elisp\" -> \"emacs-lisp\"."
  (when language
    (or (map-elt qwen-chat-shell-language-mapping
                 (downcase (string-trim language)))
        (when (intern (concat (downcase (string-trim language))
                              "-mode"))
          (downcase (string-trim language))))))

(defun qwen-chat-shell-block-action-at-point ()
  "Return t if block at point has an action.  nil otherwise."
  (let* ((source-block (qwen-chat-shell-markdown-block-at-point))
         (language (qwen-chat-shell--resolve-internal-language
                    (map-elt source-block 'language)))
         (actions (qwen-chat-shell--get-block-actions language)))
    actions
    (if actions
        actions
      (qwen-chat-shell--org-babel-command language))))

(defun qwen-chat-shell--get-block-actions (language)
  "Get block actions for LANGUAGE."
  (map-elt qwen-chat-shell-source-block-actions
           (qwen-chat-shell--resolve-internal-language
            language)))

(defun qwen-chat-shell--org-babel-command (language)
  "Resolve LANGUAGE to org babel command."
  (require 'ob)
  (when language
    (ignore-errors
      (or (require (intern (concat "ob-" (capitalize language))) nil t)
          (require (intern (concat "ob-" (downcase language))) nil t)))
    (let ((f (intern (concat "org-babel-execute:" language)))
          (f-cap (intern (concat "org-babel-execute:" (capitalize language)))))
      (if (fboundp f)
          f
        (if (fboundp f-cap)
            f-cap)))))

(defun qwen-chat-shell-execute-block-action-at-point ()
  "Execute block at point."
  (interactive)
  (if-let ((block (qwen-chat-shell-markdown-block-at-point)))
      (if-let ((actions (qwen-chat-shell--get-block-actions (map-elt block 'language)))
               (action (map-elt actions 'primary-action))
               (confirmation (map-elt actions 'primary-action-confirmation))
               (default-directory "/tmp"))
          (when (y-or-n-p confirmation)
            (funcall action (buffer-substring-no-properties
                             (map-elt block 'start)
                             (map-elt block 'end))))
        (if (and (map-elt block 'language)
                 (qwen-chat-shell--org-babel-command
                  (qwen-chat-shell--resolve-internal-language
                   (map-elt block 'language))))
            (qwen-chat-shell-execute-babel-block-action-at-point)
          (user-error "No primary action for %s blocks" (map-elt block 'language))))
    (user-error "No block at point")))

(defun qwen-chat-shell--override-language-params (language params)
  "Override PARAMS for LANGUAGE if found in `qwen-chat-shell-babel-headers'."
  (if-let* ((overrides (map-elt qwen-chat-shell-babel-headers
                                language))
            (temp-dir (file-name-as-directory
                       (make-temp-file "qwen-chat-shell-" t)))
            (temp-file (concat temp-dir "source-block-" language)))
      (if (cdr (assq :file overrides))
          (append (list
                   (cons :file
                         (replace-regexp-in-string (regexp-quote "<temp-file>")
                                                   temp-file
                                                   (cdr (assq :file overrides)))))
                  (assq-delete-all :file overrides)
                  params)
        (append
         overrides
         params))
    params))

(defun qwen-chat-shell-execute-babel-block-action-at-point ()
  "Execute block as org babel."
  (interactive)
  (require 'ob)
  (if-let ((block (qwen-chat-shell-markdown-block-at-point)))
      (if-let* ((language (qwen-chat-shell--resolve-internal-language
                           (map-elt block 'language)))
                (babel-command (qwen-chat-shell--org-babel-command language))
                (lang-headers (intern
                               (concat "org-babel-default-header-args:" language)))
                (bound (fboundp babel-command))
                (default-directory "/tmp"))
          (when (y-or-n-p (format "Execute %s ob block?" (capitalize language)))
            (message "Executing %s block..." (capitalize language))
            (let* ((params (org-babel-process-params
                            (qwen-chat-shell--override-language-params
                             language
                             (org-babel-merge-params
                              org-babel-default-header-args
                              (and (boundp
                                    (intern
                                     (concat "org-babel-default-header-args:" language)))
                                   (eval (intern
                                          (concat "org-babel-default-header-args:" language)) t))))))
                   (output (progn
                             (when (get-buffer org-babel-error-buffer-name)
                               (kill-buffer (get-buffer org-babel-error-buffer-name)))
                             (funcall babel-command
                                      (buffer-substring-no-properties
                                       (map-elt block 'start)
                                       (map-elt block 'end)) params)))
                   (buffer))
              (if (and output (not (stringp output)))
                  (setq output (format "%s" output))
                (when (and (cdr (assq :file params))
                           (file-exists-p (cdr (assq :file params))))
                  (setq output (cdr (assq :file params)))))
              (if (and output (not (string-empty-p output)))
                  (progn
                    (setq buffer (get-buffer-create (format "*%s block output*" (capitalize language))))
                    (with-current-buffer buffer
                      (save-excursion
                        (let ((inhibit-read-only t))
                          (erase-buffer)
                          (setq output (when output (string-trim output)))
                          (if (file-exists-p output) ;; Output was a file.
                              ;; Image? insert image.
                              (if (member (downcase (file-name-extension output))
                                          '("jpg" "jpeg" "png" "gif" "bmp" "webp"))
                                  (progn
                                    (insert "\n")
                                    (insert-image (create-image output)))
                                ;; Insert content of all other file types.
                                (insert-file-contents output))
                            ;; Just text output, insert that.
                            (insert output))))
                      (view-mode +1)
                      (setq view-exit-action 'kill-buffer))
                    (message "")
                    (select-window (display-buffer buffer)))
                (if (get-buffer org-babel-error-buffer-name)
                    (select-window (display-buffer org-babel-error-buffer-name))
                  (setq buffer (get-buffer-create (format "*%s block output*" (capitalize language))))
                  (message "No output. Check %s blocks work in your .org files." language)))))
        (user-error "No primary action for %s blocks" (map-elt block 'language)))
    (user-error "No block at point")))

(defun qwen-chat-shell-eval-elisp-block-in-ielm (text)
  "Run elisp source in TEXT."
  (qwen-chat-shell-send-to-ielm-buffer text t))

(defun qwen-chat-shell-compile-swift-block (text)
  "Compile Swift source in TEXT."
  (when-let* ((source-file (qwen-chat-shell-write-temp-file text ".swift"))
              (default-directory (file-name-directory source-file)))
    (qwen-chat-shell-run-command
     `("swiftc" ,(file-name-nondirectory source-file))
     (lambda (success output)
       (if success
           (message
            (concat (propertize "Compiles cleanly" 'face '(:foreground "green"))
                    " :)"))
         (let ((buffer (generate-new-buffer "*block error*")))
           (with-current-buffer buffer
             (save-excursion
               (insert
                (qwen-chat-shell--remove-compiled-file-names
                 (file-name-nondirectory source-file)
                 (ansi-color-apply output))))
             (compilation-mode)
             (view-mode +1)
             (setq view-exit-action 'kill-buffer))
           (select-window (display-buffer buffer)))
         (message
          (concat (propertize "Compilation failed" 'face '(:foreground "orange"))
                  " :(")))))))

(defun qwen-chat-shell-write-temp-file (content extension)
  "Create a temporary file with EXTENSION and write CONTENT to it.

Return the file path."
  (let* ((temp-dir (file-name-as-directory
                    (make-temp-file "qwen-chat-shell-" t)))
         (temp-file (concat temp-dir "source-block" extension)))
    (with-temp-file temp-file
      (insert content)
      (let ((inhibit-message t))
        (write-file temp-file)))
    temp-file))

(defun qwen-chat-shell--remove-compiled-file-names (filename text)
  "Remove lines starting with FILENAME in TEXT.

Useful to remove temp file names from compilation output when
compiling source blocks."
  (replace-regexp-in-string
   (rx-to-string `(: bol ,filename (one-or-more (not (any " "))) " ") " ")
   "" text))

(provide 'qwen-chat-shell)

;;; qwen-chat-shell.el ends here
