#!/usr/bin/env python3

import yaml
from subprocess import Popen, PIPE, STDOUT, DEVNULL
import concurrent.futures
import sys
import koji as brew
import os 
import threading
import time
import argparse
from pathlib import Path

def print_line():
    print('-' * 100)

def build_image(config, test):
    print('Building an image for : {nvr}\n'.format(nvr = config['brew-package']))
    command = 'rhpkg --release pipelines-1.0-rhel-8 container-build'
    if 'repo-url' in config:
        flag = ' --repo-url="{url}"'.format(url = config['repo-url'])
        command = command + flag
    if test:
        flag = ' --scratch'
        command = command + flag
    
    proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
    (status, err) = proc.communicate()
    if not status and err:
        print('Failed the build for : {nvr}'.format(nvr = config['brew-package']))
        print(err.decode())
        raise Exception('Failed image build')

    print('Completed the build for : {nvr}'.format(nvr = config['brew-package']))
    print(status.decode())
    print_line()

def get_latest_build(builds, nvr, version):
    latest = ''
    for build_id in iter(builds.splitlines()):
        build_name = nvr + '-v' + version
        if build_name.encode() not in build_id: 
            continue
        
        latest = build_id
    return latest.decode().partition(' ')[0]

def get_image_sha(build_id):
    if not build_id: 
        print('Build id is empty')
        return

    hub = brew.ClientSession('http://brewhub.devel.redhat.com/brewhub')
    print('Fething build for ' + build_id)
    build = hub.getBuild(build_id)
    return hub.listArchives(build['build_id'])[0]['extra']['docker']['digests']['application/vnd.docker.distribution.manifest.v2+json']

def exist(env, envVars):
    for i, e in enumerate(envVars):
        if e['name'] == env:
            return i
    return -1

def mirror_image(from_img, to_img, attempt, limit):
    print('Mirroring image {from_img} ---> {to_img} : Attempt {attempt}'.format(from_img=from_img, to_img=to_img, attempt=attempt))
    print_line()
    command = 'oc image mirror --insecure {from_img} {to_img}'.format(from_img=from_img, to_img=to_img)
    proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
    (status, err) = proc.communicate()
    if not status and err:
        print('Failed to mirror image')
        print(err.decode())
        if attempt <= limit:
            print('Trying again to mirror an image')
            print_line()
            attempt +=1
            mirror_image(from_img, to_img, attempt, limit)
            return 
        print_line()
        raise Exception('Failed mirroring')
    
    print('Mirroring completed for {img}'.format(img=to_img))
    print_line()

def form_csv_name(name, version):
    return name.split('.v')[0] + '.v' + version

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='OpenShift Pipelines Productization')
    parser.add_argument('-bri', '--build-release-images', help='Want to build and releases images, true if yes default is false', type=bool, default=False)
    parser.add_argument('-bt', '--build-tests', help='Want to perform scratch build, true if yes default is false', type=bool, default=False)
    parser.add_argument('-ucsv', '--update-csv', help='Want to update CSV with released images url, true if yes default is false', type=bool, default=False)
    parser.add_argument('-bm', '--build-metadata', help='Want to build metadata, true if yes default is false', type=bool, default=False)
    parser.add_argument('-eo', '--enable-operator', help='Want to perform scratch build, true if yes default is false', type=bool, default=False)
    args = parser.parse_args()
    script_dir = os.environ['SCRIPT_DIR'] if 'SCRIPT_DIR' in os.environ else os.getcwd()
    workspace_dir = os.environ['WORKSPACE_DIR'] if 'WORKSPACE_DIR' in os.environ else Path(script_dir).parent

    #load config
    with open('image-config.yaml', 'r') as stream:
        try:
            release_config = yaml.safe_load(stream)
            print('Building the pipeline version : ' + release_config['version'])
            print_line()
        except yaml.YAMLError as exc:
            print(exc)

    #start building images
    if args.build_release_images:
        os.chdir('{root}/dist-git'.format(root=workspace_dir))
        dist_git_dir = os.getcwd()
        
        build_threads = []
        failed_builds = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
            for name, components in release_config['components'].items():
                for component in components:
                    os.chdir('{base}/{dir}'.format(base = dist_git_dir, dir = component['dir']))
                    future = executor.submit(build_image, component, args.build_tests)
                    build_threads.append(future)
                    time.sleep(5)

            for future in concurrent.futures.as_completed(build_threads):
                if future.exception():
                    failed_builds+= 1

        if failed_builds > 0:
            print('{builds} builds are failed '.format(builds=failed_builds))
            sys.exit(1)

        if args.build_tests:
            print('Build tests are completed')
            sys.exit(0)

    if args.update_csv:
        #list images
        proc = Popen(['brew list-builds --quiet --prefix="openshift-pipelines" | sort -V'], stdout=PIPE, shell=True)
        (builds, err) = proc.communicate()
        if err:
            print('Unabled to list brew builds')
            sys.exit(1)

        #get image SHA for each component
        for name, components in release_config['components'].items():
            for component in components:
                build = get_latest_build(builds, component['brew-package'], release_config['version'])
                component['image_sha'] = get_image_sha(build)
                print(component)
                print_line()

        #update operator csv manifest
        os.chdir('{root}/dist-git'.format(root=workspace_dir))
        dist_git_dir = os.getcwd()
        operator_meata = release_config['operator-meta']
        os.chdir('{base}/{dir}'.format(base = dist_git_dir, dir = operator_meata['dir']))
        with open('manifests/{ver}/openshift-pipelines-operator.v{ver}.clusterserviceversion.yaml'.format(ver = release_config['csv-semver']), 'r+') as csv_stream:
            try:
                csv = yaml.safe_load(csv_stream)
                deployment = csv['spec']['install']['spec']['deployments'][0]
                #replace operators images
                operator = release_config['components']['operator'][0]
                operator_image = release_config['registry'] + operator['name'] + '@' + operator['image_sha']
                relatedImages = []
                for container in deployment['spec']['template']['spec']['containers']:
                    if container['name'] != operator['replace']:
                        continue
                    
                    container['image'] = operator_image
                    image = {'name':container['name'].upper().replace('-', '_'), 'value':operator_image}
                    relatedImages.append(image.copy())
                    
                    for name, components in release_config['components'].items():
                        if name == 'operator':
                            continue

                        for component in components:
                            env = 'IMAGE_' + name + '_' + component['replace']
                            env = env.upper().replace('-', '_')
                            value = release_config['registry'] + component['name'] + '@' + component['image_sha']
                            envVar = {'name':env, 'value':value}
                            
                            index = exist(env, container['env'])
                            if index != -1:
                                container['env'][index]['value'] = value
                            else:
                                container['env'].append(envVar.copy())         
                            
                            relatedImages.append(envVar.copy())

                csv['metadata']['annotations']['containerImage'] = operator_image
                csv['spec']['relatedImages'] = relatedImages
                csv['spec']['version'] = release_config['version']
                csv['metadata']['name'] = form_csv_name(csv['metadata']['name'], release_config['version'])

                csv_stream.seek(0)
                csv_stream.truncate()
                yaml.safe_dump(csv, csv_stream, default_flow_style=False)

            except yaml.YAMLError as exc:
                print(exc)
                sys.exit(1)

    if args.build_metadata:
        print('Publishing the operator metadata(CSV)')
        print_line()
        os.chdir(script_dir)
        command = './meta.sh'.format(dir = script_dir)
        proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
        (status, err) = proc.communicate()
        if not status and err:
            print('Failed to execute meata build')
            print(err)
            sys.exit(1)
        print(status.decode())
        print_line()
    
    if args.enable_operator:
        print('Mirroring images')
        print_line()
        
        os.chdir(script_dir)
        command = './sync-source.sh metasync'
        proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
        (status, err) = proc.communicate()
        if not status and err:
            print('Failed to execute meatadata sync')
            print(err)
            sys.exit(1)
        print(status.decode())
        print_line()

        operator_meta = release_config['operator-meta']
        os.chdir('{root}/dist-git/{meta}'.format(root = workspace_dir, meta = operator_meta['dir']))
        with open('manifests/{ver}/openshift-pipelines-operator.v{ver}.clusterserviceversion.yaml'.format(ver = release_config['csv-semver']), 'r') as csv_stream:
            try:
                csv = yaml.safe_load(csv_stream)
            except yaml.YAMLError as exc:
                print(exc)
                sys.exit(1)
        related_mages = csv['spec']['relatedImages']
        
        mirror = release_config['mirror']
        mirror_threads = []
        failed_mirrors = 0

        with concurrent.futures.ThreadPoolExecutor(max_workers=mirror['parallel']) as executor:
            for image_url in related_mages:
                image = image_url['value'].split('/')[2]
                from_img = mirror['from-registry'] + '/' + mirror['from-org'] + '/' + mirror['from-image-prefix'] + image
                to_img = mirror['to-registry'] + '/' + mirror['to-org'] + '/' + image.split('@')[0] + ':latest'
                future = executor.submit(mirror_image, from_img, to_img, 1, mirror['retry'])
                mirror_threads.append(future)

            for future in concurrent.futures.as_completed(mirror_threads):
                if future.exception():
                    failed_mirrors+= 1

        if failed_mirrors > 0:
            print('{mirrors} mirrorings are failed '.format(mirrors=failed_mirrors))
            sys.exit(1)
        
        os.chdir(script_dir)
        command = './enable-operator.sh'
        proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
        (status, err) = proc.communicate()
        if not status and err:
            print('Failed to apply operator-config')
            print(err)
            sys.exit(1)
        print(status.decode())
        print_line()
