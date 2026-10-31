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

Ghi nguồn hiển thị trong ứng dụng nằm ở `_registerDictionaryLicenses` trong `lib/main.dart`. Nếu đổi nguồn dữ liệu thì cập nhật cả chỗ đó.

## Tạo lại danh sách

```sh
python3 -m venv /tmp/wfenv && /tmp/wfenv/bin/pip install wordfreq
curl -O https://downloads.wortschatz-leipzig.de/corpora/deu_news_2023_300K.tar.gz
tar -xzf deu_news_2023_300K.tar.gz deu_news_2023_300K/deu_news_2023_300K-sentences.txt
/tmp/wfenv/bin/python tools/keyboard-words/build_word_lists.py \
  --leipzig-de deu_news_2023_300K/deu_news_2023_300K-sentences.txt
```

## Quy tắc lọc

- Chỉ giữ từ dài từ 2 chữ trở lên và toàn là chữ cái (bỏ số, dấu nháy như `c'est`, dấu gạch).
- Tiếng Đức: một từ được viết hoa khi dạng viết hoa xuất hiện ít nhất 3 lần và nhiều hơn dạng viết thường trong kho Leipzig. Từ đứng đầu câu không được tính, để "denn", "wer" không bị viết hoa nhầm.
- Danh sách vẫn lẫn một ít lỗi chính tả phổ biến từ web (ví dụ `trés` trong tiếng Pháp). Các từ đó chỉ xếp sau từ đúng vì ít phổ biến hơn.
