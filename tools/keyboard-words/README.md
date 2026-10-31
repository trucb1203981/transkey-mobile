# Danh sách từ cho gợi ý bàn phím (DE, FR, ES, IT, PT)

`build_word_lists.py` tạo các file `words_<lang>.txt` (mỗi dòng một từ, từ phổ biến nhất đứng đầu, 12.000 từ mỗi ngôn ngữ) cho `WordSuggester` trên cả hai nền tảng:

- `android/app/src/main/assets/words_<lang>.txt`
- `ios/TransKeyKeyboard/Resources/words_<lang>.txt`

Tiếng Anh dùng `en_words.txt` có sẵn, script này không tạo lại file đó.

## Nguồn dữ liệu và giấy phép

| Nguồn | Dùng để | Giấy phép |
|---|---|---|
| [wordfreq](https://github.com/rspeer/wordfreq) (Robyn Speer) | Xếp hạng từ theo tần suất (`top_n_list`) | Dữ liệu: CC BY-SA 4.0 |
| [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de/en/download), `deu_news_2023_300K` | Khôi phục chữ hoa danh từ tiếng Đức | CC BY 4.0 |
| [Từ điển hunspell của LibreOffice](https://github.com/LibreOffice/dictionaries) (`fr`, `de_DE_frami`, `es_ES`, `it_IT`, `pt_BR`, `pt_PT`) | Loại từ viết sai chính tả, chỉ dùng lúc tạo danh sách | Theo từng từ điển (GPL/LGPL/MPL) |

Ghi nguồn hiển thị trong ứng dụng nằm ở `_registerDictionaryLicenses` trong `lib/main.dart`. Nếu đổi nguồn dữ liệu thì cập nhật cả chỗ đó. Từ điển hunspell không được đóng gói vào ứng dụng (chỉ dùng để kiểm tra lúc chạy script), nên không cần ghi ở đó.

## Tạo lại danh sách

```sh
python3 -m venv /tmp/wfenv && /tmp/wfenv/bin/pip install wordfreq spylls
curl -O https://downloads.wortschatz-leipzig.de/corpora/deu_news_2023_300K.tar.gz
tar -xzf deu_news_2023_300K.tar.gz deu_news_2023_300K/deu_news_2023_300K-sentences.txt
mkdir -p hunspell && B=https://raw.githubusercontent.com/LibreOffice/dictionaries/master
for p in fr_FR/dictionaries/fr de/de_DE_frami es/es_ES it_IT/it_IT pt_BR/pt_BR pt_PT/pt_PT; do
  for ext in dic aff; do curl -s -o "hunspell/$(basename $p).$ext" "$B/$p.$ext"; done
done
/tmp/wfenv/bin/python tools/keyboard-words/build_word_lists.py \
  --leipzig-de deu_news_2023_300K/deu_news_2023_300K-sentences.txt \
  --hunspell-dir hunspell
```

## Quy tắc lọc

- Chỉ giữ từ dài từ 2 chữ trở lên và toàn là chữ cái (bỏ số, dấu nháy như `c'est`, dấu gạch).
- Tiếng Đức: một từ được viết hoa khi dạng viết hoa xuất hiện ít nhất 3 lần và nhiều hơn dạng viết thường trong kho Leipzig. Từ đứng đầu câu không được tính, để "denn", "wer" không bị viết hoa nhầm.
- Mỗi từ phải được từ điển hunspell của ngôn ngữ đó chấp nhận. Bước này loại lỗi chính tả phổ biến trên web (`trés`, `perchè`, `tambien`, `nao`), chính tả cũ (`daß`, `idéia`), từ tiếng Anh, tiếng lóng và tên riêng viết thường. Từ chỉ được chấp nhận khi viết hoa thì giữ dạng viết hoa.
- Tiếng Đức: wordfreq đổi `ß` thành `ss` khi chuyển chữ thường (`große` thành `grosse`). Script thử khôi phục `ß` rồi mới tra từ điển, nên danh sách có `große`, `Straße`, `weiß` chứ không có `grosse`, `Strasse`.
- Không lọc theo tỉ lệ tần suất giữa các cặp chỉ khác dấu: cách đó xóa nhầm từ đúng nhưng hiếm như `él` (tiếng Tây Ban Nha), `là` (tiếng Ý), `maïs` (tiếng Pháp).
