# Code, assets and third-party notices

## Publication scope

The original GoldBrain code and project documentation are credited to Bardiya and Armiya Alizadeh (Kabir). Consult the root publication/license record for the owners' selected source terms. Historical copies may contain an older proprietary in-app copyright notice; it is preserved as historical source and must be read together with the final publication grant, not silently presented as a different author.

## Bundled audio

The supplied audio pack contains22 recordings/effects. The creator explicitly confirmed permission to redistribute these files on2026-11-01. That confirmation is the basis for supplying the original bytes. The files' original authors, licenses and any additional conditions remain applicable; an eventual GoldBrain MIT/GPL source license does not automatically license third-party recordings or grant additional sublicensing rights. No unsupported claim that the brothers composed every recording is made.

`audio-manifest.json` retains every supplied filename,size andSHA-256. The source repository retains playback code and an asset-directory README; the actual recordings are a separate release download. Use `scripts/restore_audio.py` to restore them. Public code can be studied/built without downloading the recordings; bundled playback is then unavailable.

## Other content

Supplied GoldBrain branding/images and a historical v1.0.0 promo poster accompany the source. The poster is historical marketing material, not proof that planned automated trading/prediction features shipped. Package manifests/lockfiles retain the dependencies' names and versions. Flutter/Dart,Python dependencies,platform templates,icons and provider/content rights retain their own terms. No vendor source tree,SDK,private provider subscription or market/news dataset is transferred by this repository.

## Excluded local material

Personal `.env` files,API/SMTP credentials,account/test databases and database backups,Android signing keys,private Git metadata,caches/build outputs,debug/session logs and unrelated Minecraft/IndraHub outputs are excluded. These are not needed for a new developer's fresh setup. Source examples use placeholders; bring your own authorized provider access and local database.
