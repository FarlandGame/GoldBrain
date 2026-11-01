# GoldBrain 🧠✨

**Yedi aylık büyük hedefler, öğrenme ve yarım kalmış bir finansal analiz çalışma alanı.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain, ikiz kardeşler Bardiya ve Armiya Alizadeh (Kabir) tarafından geliştirilmiş, devamı bırakılmış deneysel bir projedir. Öncelikle Farsça için tasarlanmış bir Flutter arayüzünü Python/FastAPI arka ucuyla birleştirir. Kaynak kod, başka bir geliştiricinin yapılan çalışmayı anlaması, mevcut durumu yeniden oluşturması ve nasıl devam edeceğine karar vermesi için korunmuştur.

Ortak yaratıcılar: **Bardiya Alizadeh (Kabir) · Farland_game** ve **Armiya Alizadeh (Kabir) · ArmiyaFbix**; projenin en son Hakkında ekranında ve geliştirme notlarında eşit biçimde belirtilirler.

Bardiya, çok az programlama deneyimiyle başlayıp denemeler, çevrimiçi kaynaklar ve yapay zekâ desteğiyle öğrenerek yaklaşık yedi ay çalıştığını anlatıyor. Başlangıçtaki hedef, kısa ve uzun vadeli piyasa tahminleri sunan bir Windows/Android ürünü, ardından da kullanıcının seçtiği miktardaki parasını kullanarak Wallex üzerinde otomatik işlem yapılmasıydı. Altyapı gereksinimleri, maliyetler, karmaşıklık ve finansal risk nedeniyle bu vizyonun tamamını gerçekleştirmeyi bıraktı. Bunlar tamamlanmış veya doğrulanmış yetenekler değil, hedeflerdi.

> Beynin büyük planları vardı. Altyapı faturasının da kendine göre planları vardı. 🧠🧾😅

## Korunan kaynak kodda neler var?

- 11 tema, mevcut 8 arayüz dili, animasyonlar, grafikler, ayarlar, izleme listeleri, ses denetimleri ve Hakkında sayfası içeren özel bir Flutter arayüzü.
- Standartlaştırılmış piyasa fiyatları ve geçmiş veriler, sağlayıcı köken bilgileri, güncellik ve kalite kontrolleri, kalıcı genel görünüm verileri ve veri toplama süreci içeren bir FastAPI arka ucu.
- Hesaplanan özellikler, kronolojik değerlendirme/geçmiş veri testleri ve kanıt kayıtları içeren bir araştırma tahmin motoru; bu motor, yarım kalan nihai tahmin sisteminden ayrıdır.
- Sanal alım satım API'leri; görünen portföy arayüzü ve gerçek parayla işlem yapma tamamlanmamıştır.
- E-posta doğrulama ve parola sıfırlama akışları, Argon2 ile parola koruması, JWT erişim belirteçleri, yenileme belirteci rotasyonu ve cihaz/oturum denetimleri.
- RSS haberleri, isteğe bağlı yapay zekâ makale çevirileri ve özetleri, kapsamı sınırlandırılmış salt okunur bir sohbet asistanı ve altı ülkenin piyasalarına genel bakış.
- Arka uç ve Flutter testlerinin kaynak kodları, on veritabanı geçişi, yapılandırma örnekleri, mimari/API belgeleri ve geçmiş ilerleme/karar kayıtları.

## Çalışma nerede durdu?

- 6. Aşama için planlanan, canlı çalışan ve kendi sonuçlarından geri bildirim alan tahmin sistemi yarım kalmıştır. Asistanın ilgili aracı, tahmin uydurmak yerine kullanılamadığını açıkça bildirir.
- Wallex üzerinde gerçek parayla otomatik işlem ve önerilen kullanıcı bütçesi ayırma akışı uygulanmamıştır. Borsa adaptörü taklit bir arayüz sözleşmesidir.
- Üretim kullanımına uygun veri anlaşmaları, bağımsız olarak doğrulanmış finansal performans, herkese açık dağıtım için güvenlik güçlendirmeleri ve sağlayıcılara güvenilir erişim hâlâ yapılacak işlerdir.
- Ödeme işlemleri, eksiksiz bir portföy arayüzü ve görünen bazı ayarlar yarım kalmıştır. Abonelik ve erişim hakkı modeli, tamamlanmış bir satın alma sistemi değildir.
- Mevcut bütünleşik kaynakta Windows ve web iskeletleri vardır; eski Android iskeleti ayrı olarak korunmuştur. Güncel ve çalışan bir Android veya web sürümü doğrulanmamıştır.

## Projeye devam edin

Devam rehberi, yeni klon kurulumu, mevcut durum matrisi ve doğrulama raporuyla başlayın. Geçmiş belgeler tarihleriyle birlikte korunur; içlerindeki aşama etiketleri, sağlayıcı fiyatları ve eski test sayıları mevcut kaynak kodun önüne geçmez. Kendi servis yapılandırmanızı ve yeni bir veritabanını hazırlayın. Özel hesap veritabanı, API kimlik bilgileri veya Android imzalama kimliği sağlanmaz.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Görsel kimlik ve geçmiş materyaller

Sağlanan proje posteri ve logolar eklenmiştir. Sesler, yaratıcının yeniden dağıtıma izin verildiğine ilişkin beyanına dayanarak ayrı bir varlık paketi olarak dağıtılır; kod lisansına otomatik olarak dâhil değildir. Eski kaynak kod anlık görüntüleri, mevcut uygulamanın birbirinin yerine kullanılabilen bileşenleri değil, tarihsel başvuru kaynaklarıdır.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Tarihsel tanıtım posteri: doğrulanmış güncel bir sürümü değil, projenin ilk vizyonunu gösterir."></a></p>

*Tarihsel tanıtım posteri: doğrulanmış güncel bir sürümü değil, projenin ilk vizyonunu gösterir.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Teknik devir

Ayrıntılı teknik rehberler, korunan özgün İngilizce/Farsça proje belgelerinin yanında İngilizce olarak sunulur. Bu portföy tanıtımları, portföyün geri kalanıyla aynı 18 belge dilini kullanır; uygulamanın mevcut 8 arayüz dili ayrı bir özelliktir.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Kodu veya medyayı yeniden kullanmadan önce deponun yayın/lisans kaydını ve üçüncü taraf varlıklarına ilişkin ayrı bildirimleri okuyun.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
