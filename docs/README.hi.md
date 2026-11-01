# GoldBrain 🧠✨

**सात महीने की महत्वाकांक्षा, सीखना और वित्तीय विश्लेषण का एक अधूरा कार्यक्षेत्र।**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain जुड़वाँ भाइयों Bardiya और Armiya Alizadeh (Kabir) का एक प्रायोगिक प्रोजेक्ट है, जिसका विकास बंद कर दिया गया है। इसमें मुख्यतः फ़ारसी के लिए बना Flutter इंटरफ़ेस और Python/FastAPI बैकएंड साथ काम करते हैं। सोर्स कोड इसलिए सुरक्षित रखा गया है ताकि कोई दूसरा डेवलपर किए गए काम को समझ सके, मौजूदा स्थिति दोबारा बना सके और तय कर सके कि इसे आगे कैसे बढ़ाना है।

सह-निर्माता: **Bardiya Alizadeh (Kabir) · Farland_game** और **Armiya Alizadeh (Kabir) · ArmiyaFbix**। प्रोजेक्ट के नवीनतम About पेज और विकास संबंधी नोट्स में दोनों को बराबर श्रेय दिया गया है।

Bardiya के अनुसार इस पर लगभग सात महीने काम हुआ। शुरुआत में उन्हें प्रोग्रामिंग का बहुत कम अनुभव था और उन्होंने प्रयोगों, ऑनलाइन संसाधनों और AI की मदद से सीखा। मूल लक्ष्य Windows/Android के लिए ऐसा उत्पाद बनाना था जो बाज़ार के छोटी और लंबी अवधि के पूर्वानुमान दे, और बाद में Wallex पर स्वचालित ट्रेडिंग करे—सिर्फ़ उपयोगकर्ता द्वारा तय किए गए धन के हिस्से से। ज़रूरी बुनियादी ढाँचे, लागत, जटिलता और वित्तीय जोखिम के कारण उन्होंने इस पूरे सपने पर आगे काम करना रोक दिया। ये लक्ष्य थे, पूरी हो चुकी या सत्यापित क्षमताएँ नहीं।

> दिमाग़ ने बड़े प्लान बनाए थे। इंफ़्रास्ट्रक्चर के बिल ने भी अपने प्लान बना रखे थे। 🧠🧾😅

## सुरक्षित रखे गए सोर्स कोड में क्या है

- अपना बनाया हुआ Flutter इंटरफ़ेस, जिसमें 11 थीम, पहले से मौजूद 8 इंटरफ़ेस भाषाएँ, एनीमेशन, चार्ट, सेटिंग्स, वॉचलिस्ट, ऑडियो नियंत्रण और About पेज हैं।
- FastAPI बैकएंड, जिसमें मानकीकृत बाज़ार भाव और ऐतिहासिक डेटा, डेटा प्रदाता का स्रोत, डेटा की ताज़गी और गुणवत्ता की जाँच, स्थायी रूप से सहेजा गया अवलोकन डेटा और डेटा संग्रह वर्कर हैं।
- शोध के लिए पूर्वानुमान इंजन, जिसमें फ़ीचर गणना, समयक्रम के अनुसार मूल्यांकन और बैकटेस्टिंग, तथा साक्ष्य रिकॉर्ड हैं; यह अधूरे अंतिम पूर्वानुमान सिस्टम से अलग है।
- नकली धन से अभ्यास करने के लिए पेपर-ट्रेडिंग API; दिखने वाला पोर्टफ़ोलियो UI और असली धन से ट्रेडिंग अधूरे हैं।
- ईमेल सत्यापन और पासवर्ड रीसेट की प्रक्रियाएँ, Argon2 पासवर्ड प्रबंधन, JWT एक्सेस टोकन, रिफ्रेश टोकन रोटेशन और डिवाइस/सेशन नियंत्रण।
- RSS समाचार, वैकल्पिक AI लेख अनुवाद और सारांश, सीमित अधिकारों वाला केवल-पढ़ने का चैट सहायक और छह देशों का मार्केट पल्स संकेतक।
- बैकएंड और Flutter के टेस्ट सोर्स, डेटाबेस के दस माइग्रेशन, कॉन्फ़िगरेशन उदाहरण, आर्किटेक्चर/API दस्तावेज़ और प्रगति व निर्णयों के ऐतिहासिक रिकॉर्ड।

## काम कहाँ रुका

- नियोजित Phase 6 का लाइव/स्व-फ़ीडबैक पूर्वानुमान सिस्टम अधूरा है। उसका सहायक टूल पूर्वानुमान गढ़ने के बजाय साफ़ बताता है कि वह उपलब्ध नहीं है।
- Wallex पर असली धन से स्वचालित ट्रेडिंग और उपयोगकर्ता का बजट आवंटित करने की प्रस्तावित प्रक्रिया लागू नहीं हुई। एक्सचेंज अडैप्टर केवल एक नकली इंटरफ़ेस अनुबंध है।
- वास्तविक संचालन के लिए डेटा समझौते, स्वतंत्र रूप से सत्यापित वित्तीय प्रदर्शन, सार्वजनिक डिप्लॉयमेंट की सुरक्षा और विश्वसनीयता बढ़ाना, तथा प्रदाताओं तक भरोसेमंद पहुँच अभी बाकी काम हैं।
- भुगतान प्रोसेसिंग, पूरा पोर्टफ़ोलियो UI और दिखने वाली कुछ सेटिंग्स अधूरी हैं। सब्सक्रिप्शन/उपयोग-अधिकार मॉडल होना, पूरा चेकआउट सिस्टम होने के बराबर नहीं है।
- मौजूदा एकीकृत सोर्स में Windows और वेब के आधारभूत ढाँचे हैं; पुराना Android ढाँचा अलग सुरक्षित रखा गया है। मौजूदा Android या वेब रिलीज़ के ठीक से काम करने का सत्यापन नहीं हुआ है।

## प्रोजेक्ट आगे बढ़ाएँ

आगे विकास करने की गाइड, नए क्लोन का सेटअप, मौजूदा स्थिति की तालिका और सत्यापन रिपोर्ट से शुरू करें। ऐतिहासिक दस्तावेज़ उनकी तारीख़ों के साथ सुरक्षित हैं; उनमें दिए चरणों के नाम, प्रदाताओं की कीमतें और पुराने टेस्ट की गिनती मौजूदा सोर्स से ऊपर नहीं मानी जानी चाहिए। अपनी सेवा कॉन्फ़िगरेशन और नया डेटाबेस इस्तेमाल करें। निजी अकाउंट डेटाबेस, API क्रेडेंशियल या Android साइनिंग पहचान उपलब्ध नहीं कराई गई है।

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## ब्रांडिंग और ऐतिहासिक सामग्री

दिए गए प्रोजेक्ट पोस्टर और लोगो शामिल हैं। निर्माता के इस कथन के आधार पर कि पुनर्वितरण की अनुमति है, ऑडियो अलग एसेट पैक में दिया जाता है; कोड का लाइसेंस उस पर अपने-आप लागू नहीं होता। पुराने सोर्स स्नैपशॉट ऐतिहासिक संदर्भ हैं, मौजूदा ऐप के आपस में बदलकर इस्तेमाल किए जा सकने वाले हिस्से नहीं।

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="पुराना प्रचार पोस्टर: यह परियोजना की मूल कल्पना दिखाता है, सत्यापित वर्तमान रिलीज़ नहीं।"></a></p>

*पुराना प्रचार पोस्टर: यह परियोजना की मूल कल्पना दिखाता है, सत्यापित वर्तमान रिलीज़ नहीं।*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## तकनीकी हैंडऑफ़

विस्तृत तकनीकी गाइड अंग्रेज़ी में हैं और प्रोजेक्ट के मूल अंग्रेज़ी/फ़ारसी दस्तावेज़ भी सुरक्षित रखे गए हैं। ये पोर्टफ़ोलियो परिचय बाकी पोर्टफ़ोलियो की तरह उन्हीं 18 दस्तावेज़ी भाषाओं में हैं; ऐप की पहले से मौजूद 8 इंटरफ़ेस भाषाएँ एक अलग सुविधा हैं।

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

कोड या मीडिया दोबारा इस्तेमाल करने से पहले रिपॉज़िटरी का प्रकाशन/लाइसेंस रिकॉर्ड और थर्ड-पार्टी एसेट की अलग सूचनाएँ पढ़ें।

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
