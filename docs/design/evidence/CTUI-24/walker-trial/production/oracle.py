import tempfile,pathlib,subprocess,json,os,shutil
evidence=pathlib.Path(__file__).resolve().parent
root=pathlib.Path(tempfile.mkdtemp(prefix='ctui24-discovery-'))
outside=pathlib.Path(tempfile.mkdtemp(prefix='ctui24-outside-'))
try:
 def put(name,text=''):
  p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
 put('.gitignore','*.log\nignored/\n!ignored/keep.txt\nsub/*.tmp\n')
 for name in ['.git/config','top.txt','.hidden','ignored/keep.txt','ignored/no.txt','sub/a.tmp','sub/z.txt','sub/drop.log','sub/keep.log','sub/deep/keep.log']:
  put(name)
 put('sub/.gitignore','!keep.log\n!a.tmp\n')
 (outside/'out.txt').write_text('outside')
 (root/'alias-file').symlink_to('top.txt')
 (root/'alias-dir').symlink_to('sub',target_is_directory=True)
 (root/'broken').symlink_to('missing')
 (root/'external-file').symlink_to(outside/'out.txt')
 (root/'external-dir').symlink_to(outside,target_is_directory=True)
 env=dict(os.environ)
 assert env.get('CHORD_SOURCE'), 'Set CHORD_SOURCE to the read-only original checkout'
 original=json.loads(subprocess.check_output(['bun',str(evidence/'original-discovery.ts'),str(root)],env=env))
 helper=json.loads(subprocess.check_output(['dart','--packages=example/chord/.dart_tool/package_config.json',str(evidence/'discovery.dart'),str(root)]))
 print(json.dumps({'original':original,'helper':helper,'only_original':sorted(set(original)-set(helper)),'only_helper':sorted(set(helper)-set(original))},indent=2))
finally:
 shutil.rmtree(root);shutil.rmtree(outside)
