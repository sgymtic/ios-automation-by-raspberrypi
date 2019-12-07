#!/bin/bash

# 以下の手順に従って Raspberry Pi を OTG としてセットアップし、iPhone に接続する。
# https://gist.github.com/gbaman/975e2db164b3ca2b51ae11e45e8fd40a

# Raspberry Pi の接続情報
PI_MOUSE_HOST="192.168.1.2"
PI_MOUSE_USER="pi"

# パターン認識によるタップ座標検出を使用する場合、iOS端末の画面をPC上に表示する仕組みが必要。
# 最初に考えられるのはQuickTime Playerだが、端子が専有されるのでRasberry Piを有線接続出来ない。
# 画面ミラーリング等の別の手段でiOS端末の画面をPC上に表示するか、Bluetoothなど別の方法でRasberry Piを接続する必要がある。
# 後者がそもそも可能かどうかは未調査。
#
# パターン認識を利用する場合、以下のツールを利用する
#
# [imagemagick]
# 1. brew install imagemagick
#
# [visgrep]
# 1. https://www.hoopajoo.net/projects/xautomation.html からダウンロード
# 2. ./configure
# 3. make visgrep
#   - xquartz が存在しない場合は brew cask install xquartz 後に make visgrep CC='gcc -I/opt/X11/include'
# 4. cp ./visgrep /usr/local/bin/
#
# [terreract]
# 1. brew install tesseract
# 2. wget -P /usr/local/share/tessdata/ https://github.com/tesseract-ocr/tessdata/raw/master/jpn.traineddata 
# 3. wget -P /usr/local/share/tessdata/ https://github.com/tesseract-ocr/tessdata/raw/master/jpn_vert.traineddata
# 4. wget -P /usr/local/share/tessdata/ https://github.com/tesseract-ocr/tessdata/raw/master/eng.traineddata

SCREEN_CAPTURE_FILE="./screenshot/screen.png"

# このコマンドが実行後、任意の手法で取得したiOS端末の全画面のスクリーンショットが SCREEN_CAPTURE_FILE に出力されていることを期待する。
SCREEN_CAPTURE_COMMAND="screencapture -R 467,38,344,746 $SCREEN_CAPTURE_FILE"

# visgrep 時に torelance として指定される値
# 低いと全然ヒットしないので絶妙なバランスが求められる…。
TOLERANCE=300000

# tesseract 使用時の一時ファイル置き場
TESSERACT_TMPFILE_PATH="./tesseract/"

# 端末で端から端までマウスが移動する時の合計移動量
# 設定 > アクセシビリティ > タッチ > AssistiveTouch > 軌跡の速さ を調整した後に計測する。
# 現状は手動で計測する必要があるが、自動化すると便利そうではある。
# 以下の 300, 300 は iPhone 11 において一番移動量が多くなるように設定した場合のもの。
MOUSE_WIDTH=300
MOUSE_HEIGHT=300

# 端末のサイズ（ポイント数）
DEVICE_WIDTH=414
DEVICE_HEIGHT=896

# タップ時に左クリックを押し続ける時間
TAP_TIME=0.1
# 長押し時に左クリックを押し続ける時間
LONGPRESS_TIME=1.0
# tap, swipe, longpress の操作後にデフォルトで待機する時間
WAIT_TIME=1.0
# 画像と文字列から位置を検出する時間の上限
LIMIT_TIME=30

# 1ならデバッグログを標準エラー出力に書き出す
DEBUG=1


# 変数
CURSOR_X=0
CURSOR_Y=0

# マウスカーソルを目一杯左上に移動してスクリプト内で保持するCURSORの値と辻褄を合わせる
reset() {
	CURSOR_X="$MOUSE_WIDTH"; CURSOR_Y="$MOUSE_HEIGHT"
	_moveto 0 0
}

# 指定された位置をタップする。
# $1: 位置を指定するパラメータ
#  - 座標(ポイント) 例: "(100,-100)" ※ 負数の場合、画面右/下端からの距離になる
#  - 座標(%) 例: "(50%, 50%)"
#  - 画像 例: "icon.png"
#  - 文字列 例: "設定"
# $2: $1で指定した結果から座標をずらす量。文字列の表示位置の上のアイコンをタップする場合などに使用する。
tap() {
	if [ "$#" -eq "2" ]; then DIFF="$2"; else DIFF="(0,0)"; fi
	POINT=`_param2point "$1" "$DIFF"`
	if [ -n "$POINT" ]; then
		_moveto $POINT
		_click $TAP_TIME
		sleep $WAIT_TIME
	else
		_error "タップする対象が見つかりません。"
		exit 2
	fi
}

# 指定した位置を長押しする。
# $1: 位置を指定するパラメータ
# $2: $1で指定した結果から座標をずらす量
longpress() {
	if [ "$#" -eq 2 ]; then DIFF="$2"; else DIFF="(0,0)"; fi
	POINT=`_param2point "$1" "$DIFF"`
	if [ -n "$POINT" ]; then
		_moveto $POINT
		_click $LONGPRESS_TIME
		sleep $WAIT_TIME
	else
		_error "長押しする対象が見つかりません"
		exit 2
	fi
}

# 指定した位置から次に指定した位置までドラッグします。
# $1: スワイプ開始位置を指定するパラメータ
# $2: スワイプ終了位置を指定するパラメータ
# $3: $1で指定した結果から座標をずらす量。
# $4: $2で指定した結果から座標をずらす量。
swipe() {
	if [ "$#" -le 3 ]; then
		DIFF1="(0,0)"; DIFF2="(0,0)";
	else
		DIFF1=$3; DIFF2=$4;
	fi
	FROM=`_param2point "$1" "$DIFF1"`; TO=`_param2point "$2" "$DIFF2"`
	if [ -n "$FROM" -a -n "$TO" ]; then
		_moveto $FROM
		_on
		_moveto $TO 1
		_off
		sleep $WAIT_TIME
	else
		_error "ドラッグする対象が見つかりません"
		exit 2
	fi
}

# 指定されたパターンの位置を返す。形式は座標(ポイント) 。
# $1: 位置を指定するパラメータ
# $2: $1で指定した結果から座標をずらす量
point() {
	if [ "$#" -eq 2 ]; then DIFF="$2"; else DIFF="(0,0)"; fi
	POINT=`_param2point "$1" "$DIFF"`
	if [ -n "$POINT" ]; then
		POINT_X=`echo $POINT | sed "s/\([0-9]*\) [0-9]*/\1/"`
		POINT_Y=`echo $POINT | sed "s/[0-9]* \([0-9]*\)/\1/"`
		X=$(($POINT_X * $DEVICE_WIDTH / $MOUSE_WIDTH)); Y=$(($POINT_Y * $DEVICE_HEIGHT / $MOUSE_HEIGHT))
		echo "($X,$Y)"
	else
		_error "対象が見つかりません"
		exit 2
	fi

}

# 指定されたパターンが画面上に存在することを確認する。存在しない場合はエラーになる。
# $1: 位置を指定するパラメータ
assertExists() {
	POINT=`_param2point $1`
	if [ -n "$POINT" ]; then
		echo $POINT
	else
		_error "対象が見つかりません"
		exit 2
	fi
}

# 位置指定のパラメータをカーソル座標に変換する
# $1: 位置を指定するパラメータ
# $2: $1で指定した結果から座標をずらす量
_param2point() {
	_debug "_param2point $1 $2"
	DEVICE_POINT=`echo "$1" | sed "s/ //g" | grep -e "^(-*[0-9]*,-*[0-9]*)$"`
	PERCENT_POINT=`echo "$1" | sed "s/ //g" | grep -e "^([0-9]*%,[0-9]*%)$"`
	if [ -n "$DEVICE_POINT" ]; then
		POINT=`_devicepoint2point "$DEVICE_POINT"`
	elif [ -n "$PERCENT_POINT" ]; then
		POINT=`_percentpoint2point "$PERCENT_POINT"`
	else
		POINT=`_pattern2point "$1"`
	fi

	if [ -n "$POINT" ]; then
		_shift $POINT "$2"
	else
		_error "位置の検出に失敗しました"	
	fi
}

# 指定された$1 $2のカーソル座標を$3だけずらす
_shift() {
	_debug "_shift $1 $2 $3"

	SHIFT=`echo "$3" | sed "s/ //g" | grep -e "^(-*[0-9]*,-*[0-9]*)$"`
	if [ -n "$SHIFT" ]; then
		SHIFT_X=`echo "$SHIFT" | sed "s/^(\(-*[0-9]*\),-*[0-9]*)$/\1/"`
		SHIFT_Y=`echo "$SHIFT" | sed "s/^(-*[0-9]*,\(-*[0-9]*\))$/\1/"`
		X=$(($1 + $SHIFT_X * $MOUSE_WIDTH / $DEVICE_WIDTH))
		Y=$(($2 + $SHIFT_Y * $MOUSE_HEIGHT / $DEVICE_HEIGHT))
		if [ \( "$X" -lt $((0 - $MOUSE_WIDTH)) -o "$X" -gt "$MOUSE_WIDTH" \) -a \( "$Y" -lt $((0 - $MOUSE_HEIGHT)) -o "$Y" -gt "$MOUSE_HEIGHT" \) ]; then
			_error "シフト指定の値が不正です"
		else
			echo "$X $Y"
		fi
	else
		_error "シフト指定のフォーマットが不正です"
	fi
}

# 指定された座標（ポイント）をカーソル座標に変換する
_devicepoint2point() {
	_debug "_devicepoint2point $1"
	X=`echo $1 | sed "s/(\(-*[0-9]*\),-*[0-9]*)/\1/"`
	Y=`echo $1 | sed "s/(-*[0-9]*,\(-*[0-9]*\))/\1/"`

	if [ "$X" -lt 0 ]; then X=$(($X + $DEVICE_WIDTH)); fi
	if [ "$Y" -lt 0 ]; then Y=$(($Y + $DEVICE_HEIGHT)); fi

	if [ \( "$X" -lt $((0 - $DEVICE_WIDTH)) -o "$X" -gt "$DEVICE_WIDTH" \) -a \( "$Y" -lt $((0 - $DEVICE_HEIGHT)) -o "$Y" -gt "$DEVICE_HEIGHT" \) ]; then
		echo ""
	else
		echo "$(($X * $MOUSE_WIDTH / $DEVICE_WIDTH)) $(($Y * $MOUSE_HEIGHT / $DEVICE_HEIGHT))"
	fi
}

# 指定された座標（％）をカーソル座標に変換する
_percentpoint2point() {
	_debug "_percentpoint2point $1"
	X=`echo $1 | sed "s/(\([0-9]*\)%,[0-9]*%)/\1/"`
	Y=`echo $1 | sed "s/([0-9]*%,\([0-9]*\)%)/\1/"`
	if [ \( "$X" -lt 0 -o "$X" -gt 100 \) -a \( "$Y" -lt 0 -o "$Y" -gt 100 \) ]; then
		echo ""
	else
		echo "$(($X * $MOUSE_WIDTH / 100)) $(($Y * $MOUSE_HEIGHT / 100))"
	fi
}

# 指定されたパターン（画像または文字列）から位置を検出し、カーソル座標に変換する
_pattern2point() {
	START_TIME=`date +%s`
	while [ $((`date +%s` - $START_TIME)) -lt $LIMIT_TIME ]
	do
		_capture
		if [ \( `basename $1 .png` != `basename $1` -o `basename $1 .PNG` != `basename $1` \) -a -e "$1" ]; then
			RESULT=`_detect_image "$1"`
		else
			RESULT=`_detect_text "$1"`
		fi
		if [ -n "$RESULT" ]; then
			echo $RESULT
			break
		else
			_warn "パターンから位置を検出出来なかったので再試行します"
		fi
	done
}

# iOSの画面のスクリーンショットを取得する
# 実際にどういう方法で取得するかは $SCREEN_CAPTURE_COMMAND による
_capture() {
  # iOS端末の現在のスクリーンショットを取得する
  $SCREEN_CAPTURE_COMMAND
  # スクリーンショットの画像サイズを取得する
  SCREEN_CAPTURE_WIDTH=`identify -format "%[width]" $SCREEN_CAPTURE_FILE`
  SCREEN_CAPTURE_HEIGHT=`identify -format "%[height]" $SCREEN_CAPTURE_FILE`	
}

# 引数で与えられた画像の座標位置を返す
_detect_image() {
	_debug "_detect_image $1"
	RESULT=`visgrep -t "$TOLERANCE" "$SCREEN_CAPTURE_FILE" "$1" | head -n1 | grep -e "^[0-9]*,[0-9]* .*"`
	if [ -n "$RESULT" ]; then
		WIDTH=`identify -format "%[width]" $1`
		HEIGHT=`identify -format "%[height]" $1`
		X=`echo "${RESULT}" | sed "s/\([0-9]*\),[0-9]* -1/\1/"`
		Y=`echo "${RESULT}" | sed "s/[0-9]*,\([0-9]*\) -1/\1/"`
		MOUSE_X="$((($X + ($WIDTH / 2)) * $MOUSE_WIDTH / $SCREEN_CAPTURE_WIDTH))"
		MOUSE_Y="$((($Y + ($HEIGHT / 2)) * $MOUSE_HEIGHT / $SCREEN_CAPTURE_HEIGHT))"
		echo "${MOUSE_X} ${MOUSE_Y}"
	else
  		_debug "$1 is not detected"
  		echo ""
	fi
}

# 引数で与えられた文字列の座標位置を返す
# 文字検出にはOCRツールである tesseract を利用する。
# 画像から特定の文字列を探すのではなく、まず画像すべての文字列を抽出し、そこから特定の文字列を探す方法を採る。
# かなり無駄感が否めないが、かなり手軽に文字列検出が出来る方法である。
_detect_text() {
	_debug "_detect_text $1"
	POINT=""
	#前処理として二値化を行う。適切な閾値は条件によって様々なので複数試す。
	for THRESHOLD in 60 30 0 90 
	do
		if [ $THRESHOLD -gt 0 ]; then 
			convert -threshold "${THRESHOLD}%" -strip -alpha off "$SCREEN_CAPTURE_FILE" "${TESSERACT_TMPFILE_PATH}threshould-$THRESHOLD.png"
		else
			cp "$SCREEN_CAPTURE_FILE" "${TESSERACT_TMPFILE_PATH}threshould-$THRESHOLD.png"
		fi
		EXPECTED_TEXT=`echo $1 | sed "s/ //g"`
		TEXT=""; X=""; Y="";

		# 検出する文字列が英数字のみであれば英語、そうでなければ日本語を指定する。。
		ALNUM_PUNCT=`echo "$EXPECTED_TEXT" | grep "^[[:alnum:][:punct:]]*$"`
		if [ -n "$ALNUM_PUNCT" ]; then
			LANGUAGE="eng"
		else
			LANGUAGE="jpn"
		fi
		tesseract "${TESSERACT_TMPFILE_PATH}threshould-$THRESHOLD.png" "${TESSERACT_TMPFILE_PATH}result-$THRESHOLD" --psm 11 -l "$LANGUAGE" tsv > "${TESSERACT_TMPFILE_PATH}console.log" 2>&1
		
		# tsvにはN-gram区切りで1行毎にその文字列、検出位置、幅と高さ等が記載されている。
		# 連続する行の文字列を結合(先頭が一致しなくなったらリセット)していき、期待する文字列と一致したら検出したとみなす。
		# 最初の文字列の検出位置座標を覚えておけば、最後の文字列にある検出位置と幅高さを元に文字列全体の検出位置を計算出来る。
		while read LINE
		do
			LINE=($LINE)
			TEXT="$TEXT${LINE[11]}"
			COUNT="${#TEXT}"
			if [ "$COUNT" -gt 0 ]; then
				if [ "`echo $EXPECTED_TEXT | cut -c 1-$COUNT`" = "$TEXT" ]; then
					if [ -z "$X" ]; then X="${LINE[6]}"; fi
					if [ -z "$Y" ]; then Y="${LINE[7]}"; fi
					if [ "$TEXT" = "$EXPECTED_TEXT" ]; then
						WIDTH=$((${LINE[6]} + ${LINE[8]} - $X))
						HEIGHT=$((${LINE[7]} + ${LINE[9]} - $Y))
						break
					fi
				else
					TEXT=""; X=""; Y="";
				fi
			else
				TEXT=""; X=""; Y="";
			fi
		done < "${TESSERACT_TMPFILE_PATH}result-$THRESHOLD.tsv"

		if [ -n "$WIDTH" -a -n "HEIGHT" ]; then
			MOUSE_X="$((($X + $WIDTH / 2) * $MOUSE_WIDTH / $SCREEN_CAPTURE_WIDTH))"
			MOUSE_Y="$((($Y + $HEIGHT / 2) * $MOUSE_HEIGHT / $SCREEN_CAPTURE_HEIGHT))"
			echo "${MOUSE_X} ${MOUSE_Y}"
			break
		else
			_debug "$1 is not detected on threshold=$THRESHOLD"
  		fi
	done
}

_moveto() {
	_debug "_moveto $1 $2 $3"
	if [ "$#" -le 2 ]; then
		LEFT_BUTTON=0
	else
		LEFT_BUTTON=$3
	fi
	DIFF_X=$(($1 - $CURSOR_X)); DIFF_Y=$(($2 - $CURSOR_Y))
	CURSOR_X=$1; CURSOR_Y=$2
	_move $DIFF_X $DIFF_Y $LEFT_BUTTON
}

# ボタン状態($1)と移動量($2, $3)に対応するコマンド文字列を生成する
# 移動量については-127〜127の範囲である必要がある
_move_command() {
    B=`printf "%02x\n" $3 | sed "s/.*\(..\)$/\1/"`
    X=`printf "%02x\n" $1 | sed "s/.*\(..\)$/\1/"`
    Y=`printf "%02x\n" $2 | sed "s/.*\(..\)$/\1/"`
    echo "sudo echo -ne \"\x${B}\x${X}\x${Y}\" > /dev/hidg0"
}
# 各移動量が-127〜127に収まるように move_command 複数回呼び出してコマンド文字列を生成する
_move_commands() {
    X=$1; Y=$2; COMMANDS=""
    while [ "$X" -ne 0 -o "$Y" -ne 0 ]
    do
        if [ "$X" -le 0 ]; then DIFF_X=`_max $X -127`; else DIFF_X=`_min $X 127`; fi
        if [ "$Y" -le 0 ]; then DIFF_Y=`_max $Y -127`; else DIFF_Y=`_min $Y 127`; fi
        COMMAND=`_move_command $DIFF_X $DIFF_Y $3`
        COMMANDS="$COMMANDS $COMMAND;"
        X=$(($X - $DIFF_X)); Y=$(($Y - $DIFF_Y))
    done
    echo $COMMANDS
}
# ボタン状態($1)と移動量($2, $3)を指定してマウスを操作する
_move() {
    COMMANDS=`_move_commands $1 $2 $3`
    _ssh "$COMMANDS"
}

_click() {
	_debug "_click"
	COMMANDS="sudo echo -ne \"\x1\x0\x0\" > /dev/hidg0; sleep $1; sudo echo -ne \"\x0\x0\x0\" > /dev/hidg0"
	_ssh "$COMMANDS"
}

_on() {
	COMMANDS='sudo echo -ne "\x1\x0\x0" > /dev/hidg0;'
	_ssh "$COMMANDS"
}

_off() {
	COMMANDS='sudo echo -ne "\x0\x0\x0" > /dev/hidg0;'
	_ssh "$COMMANDS"
}

_ssh() {
	ssh "pi@$PI_MOUSE_HOST" "$1"
}

_max() {
	if [ "$1" -gt "$2" ]; then echo "$1"; else echo "$2"; fi
}

_min() {
	if [ "$1" -lt "$2" ]; then echo "$1"; else echo "$2"; fi
}

_debug() {
	if [ "$DEBUG" = 1 ]; then echo "$*" >&2; fi
}

_warn() {
	echo -e "\033[0;32m$*\033[0;39m" >&2
}

_error() {
	echo -e "\033[0;31m$*\033[0;39m" >&2
}
